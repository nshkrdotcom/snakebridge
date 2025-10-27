#!/usr/bin/env bash
# Setup Python dependencies for SnakeBridge
# Uses uv by default (faster), falls back to pip if uv not available

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_DIR="$PROJECT_ROOT/priv/python"

echo "🐍 Setting up Python environment for SnakeBridge..."
echo "📁 Python directory: $PYTHON_DIR"

# Check if uv is available
if command -v uv &> /dev/null; then
    echo "✅ Using uv (fast Python package installer)"
    INSTALLER="uv pip"
else
    echo "⚠️  uv not found, falling back to pip"
    echo "💡 Install uv for faster installs: curl -LsSf https://astral.sh/uv/install.sh | sh"
    INSTALLER="pip"
fi

# Change to Python directory
cd "$PYTHON_DIR"

# Check if we're in a virtual environment
if [ -z "$VIRTUAL_ENV" ]; then
    # Prefer project-local virtualenv
    PROJECT_VENV="$PYTHON_DIR/.venv"
    SNAKEPIT_VENV="$HOME/p/g/n/snakepit/.venv"

    if [ -d "$PROJECT_VENV" ]; then
        echo "✅ Found project venv at $PROJECT_VENV"
        export VIRTUAL_ENV="$PROJECT_VENV"
        export PATH="$PROJECT_VENV/bin:$PATH"
    elif [ -d "$SNAKEPIT_VENV" ]; then
        echo "✅ Found Snakepit venv at $SNAKEPIT_VENV"
        echo "💡 Reusing Snakepit's Python environment (already has grpcio, protobuf)"
        export VIRTUAL_ENV="$SNAKEPIT_VENV"
        export PATH="$SNAKEPIT_VENV/bin:$PATH"
    else
        echo "⚠️  No virtual environment detected."
        echo "💡 Recommended: Create one for the adapter dependencies:"
        echo "   python3 -m venv $PROJECT_VENV"
        echo "   source $PROJECT_VENV/bin/activate"
        echo ""
        read -p "Continue with system Python? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
else
    echo "✅ Virtual environment detected: $VIRTUAL_ENV"
fi

# Install SnakeBridge adapter (depends on grpcio which should come from Snakepit)
echo "📦 Installing SnakeBridge Python adapter..."
$INSTALLER install -e .

# Verify installation
echo ""
echo "🔍 Verifying installation..."
python3 -c "from snakebridge_adapter import SnakeBridgeAdapter; print('✅ SnakeBridgeAdapter installed')" || {
    echo "❌ SnakeBridge adapter not found"
    exit 1
}

# Check if dependencies are available (should come from Snakepit)
python3 -c "import grpc; print(f'✅ gRPC {grpc.__version__}')" || echo "⚠️  gRPC not found - install Snakepit dependencies first"
python3 -c "import google.protobuf; print('✅ Protobuf installed')" || echo "⚠️  Protobuf not found"

echo ""
echo "✅ SnakeBridge Python setup complete!"
echo ""
echo "Next steps:"
echo "1. Run tests: mix test"
echo "2. Try example: mix run examples/api_demo.exs"
echo "3. For real Python execution, ensure Snakepit is configured"
