defmodule XTrack.Wire do
  @moduledoc """
  Wire protocol implementation for XTrack.

  Format: Length-prefixed JSON
    [4 bytes: big-endian uint32 length][JSON payload]

  This handles the serialization boundary between the typed IR
  and the bytes that go over stdio/TCP/Unix socket.
  """

  alias XTrack.IR.{
    Envelope,
    EventMeta,
    RunId,
    RunStart,
    RunEnd,
    Param,
    Metric,
    MetricBatch,
    Artifact,
    Checkpoint,
    StatusUpdate,
    LogEntry,
    Command,
    Ack
  }

  @type decode_result :: {:ok, Envelope.t()} | {:error, term()}
  @type encode_result :: {:ok, binary()} | {:error, term()}

  # ============================================================================
  # Decoding (bytes → IR)
  # ============================================================================

  @doc """
  Decode a length-prefixed frame from a binary.
  Returns {:ok, envelope, rest} or {:incomplete, needed_bytes} or {:error, reason}
  """
  @spec decode_frame(binary()) ::
          {:ok, Envelope.t(), binary()}
          | {:incomplete, non_neg_integer()}
          | {:error, term()}
  def decode_frame(<<len::big-unsigned-32, rest::binary>>) when byte_size(rest) >= len do
    <<json::binary-size(len), remaining::binary>> = rest

    case decode_json(json) do
      {:ok, envelope} -> {:ok, envelope, remaining}
      error -> error
    end
  end

  def decode_frame(<<len::big-unsigned-32, rest::binary>>) do
    {:incomplete, len - byte_size(rest)}
  end

  def decode_frame(data) when byte_size(data) < 4 do
    {:incomplete, 4 - byte_size(data)}
  end

  @doc "Decode JSON payload into an Envelope"
  @spec decode_json(binary()) :: decode_result()
  def decode_json(json) do
    with {:ok, map} <- Jason.decode(json),
         {:ok, envelope} <- map_to_envelope(map) do
      {:ok, envelope}
    else
      {:error, %Jason.DecodeError{} = e} -> {:error, {:json_decode, e}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp map_to_envelope(%{"v" => version, "t" => type_str, "m" => meta_map, "p" => payload_map}) do
    event_type = String.to_existing_atom(type_str)

    with {:ok, meta} <- decode_meta(meta_map),
         {:ok, payload} <- decode_payload(event_type, payload_map) do
      {:ok,
       %Envelope{
         version: version,
         event_type: event_type,
         meta: meta,
         payload: payload
       }}
    end
  rescue
    ArgumentError -> {:error, {:unknown_event_type, type_str}}
  end

  defp map_to_envelope(_), do: {:error, :invalid_envelope_structure}

  defp decode_meta(map) do
    {:ok,
     %EventMeta{
       seq: map["seq"],
       timestamp_us: map["ts"],
       worker_id: map["wid"],
       received_at: nil
     }}
  end

  defp decode_payload(:run_start, p) do
    {:ok,
     %RunStart{
       run_id: decode_run_id(p["run_id"]),
       name: p["name"],
       tags: p["tags"] || %{},
       source: p["source"],
       environment: p["env"]
     }}
  end

  defp decode_payload(:run_end, p) do
    {:ok,
     %RunEnd{
       run_id: p["run_id"],
       status: String.to_existing_atom(p["status"]),
       error: p["error"],
       final_metrics: p["final_metrics"] || %{},
       duration_ms: p["duration_ms"]
     }}
  end

  defp decode_payload(:param, p) do
    {:ok,
     %Param{
       run_id: p["run_id"],
       key: p["key"],
       value: p["value"],
       nested_key: p["nested_key"]
     }}
  end

  defp decode_payload(:metric, p) do
    {:ok,
     %Metric{
       run_id: p["run_id"],
       key: p["key"],
       value: p["value"],
       step: p["step"],
       epoch: p["epoch"],
       context: decode_metric_context(p["ctx"])
     }}
  end

  defp decode_payload(:metric_batch, p) do
    {:ok,
     %MetricBatch{
       run_id: p["run_id"],
       step: p["step"],
       epoch: p["epoch"],
       metrics: p["metrics"],
       context: decode_metric_context(p["ctx"])
     }}
  end

  defp decode_payload(:artifact, p) do
    {:ok,
     %Artifact{
       run_id: p["run_id"],
       path: p["path"],
       artifact_type: String.to_existing_atom(p["type"] || "other"),
       name: p["name"],
       metadata: p["meta"] || %{},
       size_bytes: p["size"],
       checksum: p["checksum"],
       upload_strategy: String.to_existing_atom(p["upload"] || "reference")
     }}
  end

  defp decode_payload(:checkpoint, p) do
    {:ok,
     %Checkpoint{
       run_id: p["run_id"],
       step: p["step"],
       epoch: p["epoch"],
       path: p["path"],
       metrics_snapshot: p["metrics"] || %{},
       is_best: p["is_best"] || false,
       best_metric_key: p["best_key"],
       metadata: p["meta"] || %{}
     }}
  end

  defp decode_payload(:status, p) do
    {:ok,
     %StatusUpdate{
       run_id: p["run_id"],
       status: String.to_existing_atom(p["status"]),
       message: p["msg"],
       progress: decode_progress(p["progress"])
     }}
  end

  defp decode_payload(:log, p) do
    {:ok,
     %LogEntry{
       run_id: p["run_id"],
       level: String.to_existing_atom(p["level"] || "info"),
       message: p["msg"],
       logger_name: p["logger"],
       step: p["step"],
       fields: p["fields"] || %{}
     }}
  end

  defp decode_payload(:ack, p) do
    {:ok,
     %Ack{
       seq: p["seq"],
       status: String.to_existing_atom(p["status"]),
       error_message: p["error"]
     }}
  end

  defp decode_payload(type, _), do: {:error, {:unhandled_event_type, type}}

  defp decode_run_id(nil), do: nil

  defp decode_run_id(map) when is_map(map) do
    %RunId{
      id: map["id"],
      experiment_id: map["exp_id"],
      parent_run_id: map["parent_id"]
    }
  end

  defp decode_run_id(id) when is_binary(id) do
    %RunId{id: id, experiment_id: nil, parent_run_id: nil}
  end

  defp decode_metric_context(nil), do: %{}

  defp decode_metric_context(ctx) do
    %{
      phase: maybe_atom(ctx["phase"]),
      batch_size: ctx["batch_size"],
      dataset_size: ctx["dataset_size"],
      aggregation: maybe_atom(ctx["agg"])
    }
  end

  defp decode_progress(nil), do: nil

  defp decode_progress(p) do
    %{
      current: p["cur"],
      total: p["total"],
      unit: p["unit"]
    }
  end

  defp maybe_atom(nil), do: nil
  defp maybe_atom(s) when is_binary(s), do: String.to_existing_atom(s)

  # ============================================================================
  # Encoding (IR → bytes)
  # ============================================================================

  @doc "Encode an envelope to a length-prefixed binary frame"
  @spec encode_frame(Envelope.t()) :: encode_result()
  def encode_frame(%Envelope{} = envelope) do
    with {:ok, json} <- encode_json(envelope) do
      len = byte_size(json)
      {:ok, <<len::big-unsigned-32, json::binary>>}
    end
  end

  @doc "Encode an envelope to JSON"
  @spec encode_json(Envelope.t()) :: encode_result()
  def encode_json(%Envelope{} = envelope) do
    map = %{
      "v" => envelope.version,
      "t" => Atom.to_string(envelope.event_type),
      "m" => encode_meta(envelope.meta),
      "p" => encode_payload(envelope.event_type, envelope.payload)
    }

    case Jason.encode(map) do
      {:ok, json} -> {:ok, json}
      {:error, e} -> {:error, {:json_encode, e}}
    end
  end

  defp encode_meta(%EventMeta{} = m) do
    %{
      "seq" => m.seq,
      "ts" => m.timestamp_us,
      "wid" => m.worker_id
    }
    |> compact()
  end

  defp encode_payload(:command, %Command{} = c) do
    %{
      "cmd_id" => c.command_id,
      "type" => Atom.to_string(c.type),
      "payload" => c.payload
    }
  end

  defp encode_payload(:ack, %Ack{} = a) do
    %{
      "seq" => a.seq,
      "status" => Atom.to_string(a.status),
      "error" => a.error_message
    }
    |> compact()
  end

  # For other types, we mainly decode from Python, but support encoding for tests
  defp encode_payload(_type, payload) when is_struct(payload) do
    Map.from_struct(payload)
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), encode_value(v)} end)
    |> Map.new()
    |> compact()
  end

  defp encode_value(%RunId{} = r),
    do: %{"id" => r.id, "exp_id" => r.experiment_id, "parent_id" => r.parent_run_id}

  defp encode_value(a) when is_atom(a) and not is_nil(a), do: Atom.to_string(a)
  defp encode_value(v), do: v

  defp compact(map) do
    map
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end
end
