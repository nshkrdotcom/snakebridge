"""
XTrack Python Emitter

Zero-dependency tracking API for Python ML training code.
Emits events to the Elixir control plane over configurable transport.

Usage:
    from xtrack import Tracker
    
    with Tracker.start_run(name="my_experiment") as run:
        run.log_params({"lr": 0.001, "batch_size": 32})
        
        for epoch in range(10):
            loss = train_epoch(...)
            run.log_metrics({"loss": loss}, step=epoch)
        
        run.log_artifact("model.pt", artifact_type="model")
"""

import json
import os
import socket
import struct
import sys
import time
import uuid
from abc import ABC, abstractmethod
from contextlib import contextmanager
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Any, Dict, List, Optional, Union, BinaryIO
import threading
import hashlib
import platform
import traceback


# ============================================================================
# Transport Abstraction
# ============================================================================

class Transport(ABC):
    """Abstract transport for sending events to the collector."""
    
    @abstractmethod
    def send(self, data: bytes) -> None:
        """Send framed data to the collector."""
        pass
    
    @abstractmethod
    def recv(self) -> Optional[bytes]:
        """Receive data from collector (for acks/commands). Non-blocking."""
        pass
    
    @abstractmethod
    def close(self) -> None:
        """Close the transport."""
        pass


class StdioTransport(Transport):
    """
    Transport over stdout/stdin.
    
    Events go to stdout (fd 3 if available, else stdout).
    Commands come from stdin.
    Training output should go to stderr.
    """
    
    def __init__(self, use_fd3: bool = True):
        self._lock = threading.Lock()
        
        # Try to use fd 3 for events (leaves stdout clean for training output)
        if use_fd3:
            try:
                self._out = os.fdopen(3, 'wb', buffering=0)
            except OSError:
                self._out = sys.stdout.buffer
        else:
            self._out = sys.stdout.buffer
        
        self._in = sys.stdin.buffer
        self._closed = False
    
    def send(self, data: bytes) -> None:
        if self._closed:
            return
        with self._lock:
            self._out.write(data)
            self._out.flush()
    
    def recv(self) -> Optional[bytes]:
        # Non-blocking read from stdin
        import select
        if select.select([self._in], [], [], 0)[0]:
            # Read length prefix
            len_bytes = self._in.read(4)
            if len(len_bytes) < 4:
                return None
            length = struct.unpack('>I', len_bytes)[0]
            return self._in.read(length)
        return None
    
    def close(self) -> None:
        self._closed = True
        if self._out not in (sys.stdout.buffer, sys.stderr.buffer):
            self._out.close()


class TCPTransport(Transport):
    """Transport over TCP socket."""
    
    def __init__(self, host: str = "localhost", port: int = 9999):
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self._sock.connect((host, port))
        self._sock.setblocking(False)
        self._lock = threading.Lock()
    
    def send(self, data: bytes) -> None:
        with self._lock:
            self._sock.sendall(data)
    
    def recv(self) -> Optional[bytes]:
        try:
            len_bytes = self._sock.recv(4)
            if len(len_bytes) < 4:
                return None
            length = struct.unpack('>I', len_bytes)[0]
            return self._sock.recv(length)
        except BlockingIOError:
            return None
    
    def close(self) -> None:
        self._sock.close()


class UnixSocketTransport(Transport):
    """Transport over Unix domain socket."""
    
    def __init__(self, path: str):
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.connect(path)
        self._sock.setblocking(False)
        self._lock = threading.Lock()
    
    def send(self, data: bytes) -> None:
        with self._lock:
            self._sock.sendall(data)
    
    def recv(self) -> Optional[bytes]:
        try:
            len_bytes = self._sock.recv(4)
            if len(len_bytes) < 4:
                return None
            length = struct.unpack('>I', len_bytes)[0]
            return self._sock.recv(length)
        except BlockingIOError:
            return None
    
    def close(self) -> None:
        self._sock.close()


class FileTransport(Transport):
    """
    Transport that writes to a file (for offline/batch processing).
    The file can be replayed to a collector later.
    """
    
    def __init__(self, path: str):
        self._file = open(path, 'ab')
        self._lock = threading.Lock()
    
    def send(self, data: bytes) -> None:
        with self._lock:
            self._file.write(data)
            self._file.flush()
    
    def recv(self) -> Optional[bytes]:
        return None  # File transport is write-only
    
    def close(self) -> None:
        self._file.close()


class NullTransport(Transport):
    """No-op transport for testing or when tracking is disabled."""
    
    def send(self, data: bytes) -> None:
        pass
    
    def recv(self) -> Optional[bytes]:
        return None
    
    def close(self) -> None:
        pass


# ============================================================================
# Wire Protocol
# ============================================================================

class Wire:
    """Length-prefixed JSON wire protocol."""
    
    @staticmethod
    def encode(envelope: dict) -> bytes:
        """Encode envelope dict to wire format."""
        json_bytes = json.dumps(envelope, separators=(',', ':')).encode('utf-8')
        length = len(json_bytes)
        return struct.pack('>I', length) + json_bytes
    
    @staticmethod
    def decode(data: bytes) -> dict:
        """Decode wire format to envelope dict."""
        if len(data) < 4:
            raise ValueError("Data too short for length prefix")
        length = struct.unpack('>I', data[:4])[0]
        json_bytes = data[4:4+length]
        return json.loads(json_bytes.decode('utf-8'))


# ============================================================================
# Event Builders
# ============================================================================

@dataclass
class EventMeta:
    seq: int
    timestamp_us: int
    worker_id: Optional[str] = None
    
    def to_dict(self) -> dict:
        d = {"seq": self.seq, "ts": self.timestamp_us}
        if self.worker_id:
            d["wid"] = self.worker_id
        return d


class EventType(Enum):
    RUN_START = "run_start"
    RUN_END = "run_end"
    PARAM = "param"
    METRIC = "metric"
    METRIC_BATCH = "metric_batch"
    ARTIFACT = "artifact"
    CHECKPOINT = "checkpoint"
    STATUS = "status"
    LOG = "log"


def make_envelope(event_type: EventType, payload: dict, seq: int, 
                  worker_id: Optional[str] = None) -> dict:
    """Create a wire-format envelope."""
    meta = EventMeta(
        seq=seq,
        timestamp_us=int(time.time() * 1_000_000),
        worker_id=worker_id
    )
    return {
        "v": 1,
        "t": event_type.value,
        "m": meta.to_dict(),
        "p": payload
    }


# ============================================================================
# Run Tracker
# ============================================================================

class Run:
    """
    Active experiment run context.
    
    Thread-safe event emission with automatic sequencing.
    """
    
    def __init__(
        self,
        run_id: str,
        transport: Transport,
        name: Optional[str] = None,
        experiment_id: Optional[str] = None,
        tags: Optional[Dict[str, str]] = None,
        worker_id: Optional[str] = None
    ):
        self.run_id = run_id
        self.experiment_id = experiment_id
        self.name = name
        self.tags = tags or {}
        self.worker_id = worker_id
        
        self._transport = transport
        self._seq = 0
        self._seq_lock = threading.Lock()
        self._start_time = time.time()
        self._ended = False
    
    def _next_seq(self) -> int:
        with self._seq_lock:
            self._seq += 1
            return self._seq
    
    def _emit(self, event_type: EventType, payload: dict) -> None:
        """Emit an event to the transport."""
        if self._ended:
            return
        
        seq = self._next_seq()
        envelope = make_envelope(event_type, payload, seq, self.worker_id)
        data = Wire.encode(envelope)
        self._transport.send(data)
    
    # ========================================================================
    # Public API
    # ========================================================================
    
    def log_param(self, key: str, value: Any, nested_key: Optional[List[str]] = None) -> None:
        """Log a single hyperparameter."""
        payload = {
            "run_id": self.run_id,
            "key": key,
            "value": value
        }
        if nested_key:
            payload["nested_key"] = nested_key
        self._emit(EventType.PARAM, payload)
    
    def log_params(self, params: Dict[str, Any]) -> None:
        """Log multiple hyperparameters."""
        for key, value in params.items():
            if isinstance(value, dict):
                # Flatten nested dicts with dot notation
                self._log_nested_params(key, value, [])
            else:
                self.log_param(key, value)
    
    def _log_nested_params(self, prefix: str, d: dict, path: List[str]) -> None:
        for k, v in d.items():
            if isinstance(v, dict):
                self._log_nested_params(prefix, v, path + [k])
            else:
                self.log_param(prefix, v, nested_key=path + [k])
    
    def log_metric(
        self,
        key: str,
        value: float,
        step: Optional[int] = None,
        epoch: Optional[int] = None,
        phase: Optional[str] = None,
        batch_size: Optional[int] = None
    ) -> None:
        """Log a single metric value."""
        payload = {
            "run_id": self.run_id,
            "key": key,
            "value": value
        }
        if step is not None:
            payload["step"] = step
        if epoch is not None:
            payload["epoch"] = epoch
        
        ctx = {}
        if phase:
            ctx["phase"] = phase
        if batch_size:
            ctx["batch_size"] = batch_size
        if ctx:
            payload["ctx"] = ctx
        
        self._emit(EventType.METRIC, payload)
    
    def log_metrics(
        self,
        metrics: Dict[str, float],
        step: Optional[int] = None,
        epoch: Optional[int] = None,
        phase: Optional[str] = None
    ) -> None:
        """Log multiple metrics atomically."""
        payload = {
            "run_id": self.run_id,
            "metrics": metrics
        }
        if step is not None:
            payload["step"] = step
        if epoch is not None:
            payload["epoch"] = epoch
        
        ctx = {}
        if phase:
            ctx["phase"] = phase
        if ctx:
            payload["ctx"] = ctx
        
        self._emit(EventType.METRIC_BATCH, payload)
    
    def log_artifact(
        self,
        path: str,
        artifact_type: str = "other",
        name: Optional[str] = None,
        metadata: Optional[dict] = None
    ) -> None:
        """Register an artifact file."""
        # Compute file info
        size_bytes = None
        checksum = None
        
        if os.path.exists(path):
            size_bytes = os.path.getsize(path)
            # SHA256 for small files
            if size_bytes < 100 * 1024 * 1024:  # < 100MB
                with open(path, 'rb') as f:
                    checksum = hashlib.sha256(f.read()).hexdigest()
        
        payload = {
            "run_id": self.run_id,
            "path": os.path.abspath(path),
            "type": artifact_type,
            "upload": "reference"
        }
        if name:
            payload["name"] = name
        if metadata:
            payload["meta"] = metadata
        if size_bytes:
            payload["size"] = size_bytes
        if checksum:
            payload["checksum"] = checksum
        
        self._emit(EventType.ARTIFACT, payload)
    
    def log_checkpoint(
        self,
        path: str,
        step: int,
        epoch: Optional[int] = None,
        metrics: Optional[Dict[str, float]] = None,
        is_best: bool = False,
        best_metric_key: Optional[str] = None
    ) -> None:
        """Record a training checkpoint."""
        payload = {
            "run_id": self.run_id,
            "step": step,
            "path": os.path.abspath(path)
        }
        if epoch is not None:
            payload["epoch"] = epoch
        if metrics:
            payload["metrics"] = metrics
        if is_best:
            payload["is_best"] = True
            if best_metric_key:
                payload["best_key"] = best_metric_key
        
        self._emit(EventType.CHECKPOINT, payload)
    
    def set_status(
        self,
        status: str,
        message: Optional[str] = None,
        progress: Optional[tuple] = None  # (current, total, unit)
    ) -> None:
        """Update run status."""
        payload = {
            "run_id": self.run_id,
            "status": status
        }
        if message:
            payload["msg"] = message
        if progress:
            payload["progress"] = {
                "cur": progress[0],
                "total": progress[1],
                "unit": progress[2] if len(progress) > 2 else "steps"
            }
        
        self._emit(EventType.STATUS, payload)
    
    def log(
        self,
        message: str,
        level: str = "info",
        step: Optional[int] = None,
        **fields
    ) -> None:
        """Log a structured message."""
        payload = {
            "run_id": self.run_id,
            "level": level,
            "msg": message
        }
        if step is not None:
            payload["step"] = step
        if fields:
            payload["fields"] = fields
        
        self._emit(EventType.LOG, payload)
    
    def end(self, status: str = "completed", error: Optional[Exception] = None) -> None:
        """End the run."""
        if self._ended:
            return
        
        duration_ms = int((time.time() - self._start_time) * 1000)
        
        payload = {
            "run_id": self.run_id,
            "status": status,
            "duration_ms": duration_ms
        }
        
        if error:
            payload["error"] = {
                "type": type(error).__name__,
                "message": str(error),
                "traceback": traceback.format_exc()
            }
        
        self._emit(EventType.RUN_END, payload)
        self._ended = True
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type:
            self.end(status="failed", error=exc_val)
        else:
            self.end(status="completed")
        self._transport.close()
        return False


# ============================================================================
# Tracker Factory
# ============================================================================

class Tracker:
    """
    Factory for creating runs with configured transport.
    
    Environment variables:
        XTRACK_TRANSPORT: stdio|tcp|unix|file|null
        XTRACK_HOST: TCP host (default: localhost)
        XTRACK_PORT: TCP port (default: 9999)
        XTRACK_SOCKET: Unix socket path
        XTRACK_FILE: File path for file transport
        XTRACK_EXPERIMENT: Default experiment ID
        XTRACK_WORKER_ID: Worker ID for distributed training
    """
    
    @staticmethod
    def _create_transport() -> Transport:
        """Create transport from environment config."""
        transport_type = os.environ.get("XTRACK_TRANSPORT", "stdio").lower()
        
        if transport_type == "stdio":
            return StdioTransport()
        elif transport_type == "tcp":
            host = os.environ.get("XTRACK_HOST", "localhost")
            port = int(os.environ.get("XTRACK_PORT", "9999"))
            return TCPTransport(host, port)
        elif transport_type == "unix":
            path = os.environ.get("XTRACK_SOCKET", "/tmp/xtrack.sock")
            return UnixSocketTransport(path)
        elif transport_type == "file":
            path = os.environ.get("XTRACK_FILE", "xtrack_events.bin")
            return FileTransport(path)
        elif transport_type == "null":
            return NullTransport()
        else:
            raise ValueError(f"Unknown transport type: {transport_type}")
    
    @staticmethod
    def _gather_environment() -> dict:
        """Gather environment info for run_start."""
        env = {
            "python_version": platform.python_version(),
            "platform": platform.platform(),
            "hostname": platform.node()
        }
        
        # Try to get GPU info
        try:
            import torch
            if torch.cuda.is_available():
                env["gpu_info"] = [
                    {
                        "name": torch.cuda.get_device_name(i),
                        "memory": torch.cuda.get_device_properties(i).total_memory
                    }
                    for i in range(torch.cuda.device_count())
                ]
        except ImportError:
            pass
        
        return env
    
    @staticmethod
    def _gather_source() -> dict:
        """Gather source control info."""
        source = {}
        
        try:
            import subprocess
            
            # Git info
            result = subprocess.run(
                ["git", "rev-parse", "HEAD"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                source["git_commit"] = result.stdout.strip()
            
            result = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                source["git_branch"] = result.stdout.strip()
            
            result = subprocess.run(
                ["git", "remote", "get-url", "origin"],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0:
                source["git_repo"] = result.stdout.strip()
        except Exception:
            pass
        
        return source
    
    @classmethod
    def start_run(
        cls,
        name: Optional[str] = None,
        run_id: Optional[str] = None,
        experiment_id: Optional[str] = None,
        tags: Optional[Dict[str, str]] = None,
        transport: Optional[Transport] = None
    ) -> Run:
        """
        Start a new experiment run.
        
        Args:
            name: Human-readable run name
            run_id: Explicit run ID (auto-generated if not provided)
            experiment_id: Parent experiment ID
            tags: Key-value tags for the run
            transport: Custom transport (uses env config if not provided)
        
        Returns:
            Run context manager
        """
        if transport is None:
            transport = cls._create_transport()
        
        if run_id is None:
            run_id = str(uuid.uuid4())
        
        if experiment_id is None:
            experiment_id = os.environ.get("XTRACK_EXPERIMENT")
        
        worker_id = os.environ.get("XTRACK_WORKER_ID")
        
        run = Run(
            run_id=run_id,
            transport=transport,
            name=name,
            experiment_id=experiment_id,
            tags=tags or {},
            worker_id=worker_id
        )
        
        # Emit run_start event
        payload = {
            "run_id": {
                "id": run_id,
                "exp_id": experiment_id
            },
            "name": name,
            "tags": tags or {},
            "source": cls._gather_source(),
            "env": cls._gather_environment()
        }
        
        run._emit(EventType.RUN_START, payload)
        run.set_status("running")
        
        return run


# ============================================================================
# Convenience Functions (MLflow-style API)
# ============================================================================

_active_run: Optional[Run] = None


def start_run(**kwargs) -> Run:
    """Start a run and set it as the active run."""
    global _active_run
    _active_run = Tracker.start_run(**kwargs)
    return _active_run


def end_run(status: str = "completed") -> None:
    """End the active run."""
    global _active_run
    if _active_run:
        _active_run.end(status)
        _active_run = None


def log_param(key: str, value: Any) -> None:
    """Log a param to the active run."""
    if _active_run:
        _active_run.log_param(key, value)


def log_params(params: Dict[str, Any]) -> None:
    """Log params to the active run."""
    if _active_run:
        _active_run.log_params(params)


def log_metric(key: str, value: float, step: Optional[int] = None) -> None:
    """Log a metric to the active run."""
    if _active_run:
        _active_run.log_metric(key, value, step=step)


def log_metrics(metrics: Dict[str, float], step: Optional[int] = None) -> None:
    """Log metrics to the active run."""
    if _active_run:
        _active_run.log_metrics(metrics, step=step)


def log_artifact(path: str, artifact_type: str = "other") -> None:
    """Log an artifact to the active run."""
    if _active_run:
        _active_run.log_artifact(path, artifact_type)


def set_status(status: str, message: Optional[str] = None) -> None:
    """Set status on the active run."""
    if _active_run:
        _active_run.set_status(status, message)


# ============================================================================
# Framework Integrations
# ============================================================================

class AxonCallback:
    """
    Callback adapter for Axon training loops (via Pythex/Snakepit).
    
    This is a stub showing the interface - actual implementation
    depends on how Axon exposes its loop events to Python.
    """
    
    def __init__(self, run: Run):
        self.run = run
    
    def on_epoch_start(self, epoch: int, state: dict) -> None:
        self.run.set_status("training", progress=(epoch, state.get("epochs", 0), "epochs"))
    
    def on_epoch_end(self, epoch: int, state: dict) -> None:
        metrics = {k: v for k, v in state.items() if isinstance(v, (int, float))}
        self.run.log_metrics(metrics, epoch=epoch)
    
    def on_step_end(self, step: int, state: dict) -> None:
        if step % 100 == 0:  # Log every 100 steps
            metrics = {k: v for k, v in state.items() if isinstance(v, (int, float))}
            self.run.log_metrics(metrics, step=step)


class PyTorchCallback:
    """
    Callback for PyTorch training loops.
    
    Usage:
        callback = PyTorchCallback(run)
        
        for epoch in range(epochs):
            callback.on_epoch_start(epoch)
            for batch in dataloader:
                loss = train_step(batch)
                callback.on_step_end(step, {"loss": loss})
            callback.on_epoch_end(epoch, {"val_loss": val_loss})
    """
    
    def __init__(self, run: Run, log_every_n_steps: int = 100):
        self.run = run
        self.log_every_n_steps = log_every_n_steps
        self._step = 0
    
    def on_epoch_start(self, epoch: int, total_epochs: Optional[int] = None) -> None:
        self.run.set_status(
            "training",
            message=f"Epoch {epoch}",
            progress=(epoch, total_epochs, "epochs") if total_epochs else None
        )
    
    def on_epoch_end(self, epoch: int, metrics: Dict[str, float]) -> None:
        self.run.log_metrics(metrics, epoch=epoch)
    
    def on_step_end(self, step: int, metrics: Dict[str, float]) -> None:
        self._step = step
        if step % self.log_every_n_steps == 0:
            self.run.log_metrics(metrics, step=step)
    
    def on_checkpoint(
        self,
        path: str,
        metrics: Dict[str, float],
        is_best: bool = False,
        best_metric: Optional[str] = None
    ) -> None:
        self.run.log_checkpoint(
            path=path,
            step=self._step,
            metrics=metrics,
            is_best=is_best,
            best_metric_key=best_metric
        )


if __name__ == "__main__":
    # Demo usage
    with Tracker.start_run(name="demo_run") as run:
        run.log_params({
            "learning_rate": 0.001,
            "batch_size": 32,
            "optimizer": {
                "type": "adam",
                "beta1": 0.9,
                "beta2": 0.999
            }
        })
        
        for epoch in range(3):
            run.set_status("training", progress=(epoch + 1, 3, "epochs"))
            for step in range(100):
                loss = 1.0 / (step + 1 + epoch * 100)
                if step % 10 == 0:
                    run.log_metrics({"loss": loss, "lr": 0.001}, step=epoch * 100 + step)
            
            run.log_metrics({"val_loss": 0.1 / (epoch + 1)}, epoch=epoch)
        
        run.log("Training complete", level="info")
