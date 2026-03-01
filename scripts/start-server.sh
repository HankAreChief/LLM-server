#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env
[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
HOST="${MLX_SERVER_HOST:-0.0.0.0}"
PORT="${MLX_SERVER_PORT:-8080}"
DEFAULT_MODEL_REPO="${DEFAULT_MODEL:-mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit}"
HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"

LOG_DIR="$PROJECT_DIR/logs"
PID_FILE="$LOG_DIR/server.pid"

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --model <alias|hf_repo>   Model to load (alias from models.json or full HF repo)
  -h, --help                Show this help

Examples:
  $(basename "$0")                                           # Use DEFAULT_MODEL from .env
  $(basename "$0") --model llama-3.3-70b                   # Use alias
  $(basename "$0") --model mlx-community/Qwen3-32B-4bit    # Use HF repo directly
EOF
    exit 0
}

MODEL_ARG=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --model) MODEL_ARG="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Activate venv
VENV="$PROJECT_DIR/.venv"
if [ -f "$VENV/bin/activate" ]; then
    source "$VENV/bin/activate"
else
    echo "ERROR: Virtual environment not found. Run ./scripts/install.sh first."
    exit 1
fi

# Resolve model alias -> HF repo
resolve_model() {
    local model_arg="$1"

    [ -z "$model_arg" ] && { echo "$DEFAULT_MODEL_REPO"; return; }

    # Direct HF repo (contains /)
    [[ "$model_arg" == *"/"* ]] && { echo "$model_arg"; return; }

    # Look up alias in models.json
    MODELS_JSON="$PROJECT_DIR/config/models.json" MODEL_ALIAS="$model_arg" python3 - <<'PYEOF'
import json, os, sys
with open(os.environ['MODELS_JSON']) as f:
    data = json.load(f)
alias = os.environ['MODEL_ALIAS']
if alias in data['fleet']:
    print(data['fleet'][alias]['hf_repo'])
else:
    available = ', '.join(data['fleet'].keys())
    print(f"ERROR: Unknown model alias '{alias}'.", file=sys.stderr)
    print(f"Available: {available}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

# Check if server is already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Server is already running (PID $OLD_PID)."
        echo "Use ./scripts/switch-model.sh to change models, or kill PID $OLD_PID manually."
        exit 1
    else
        rm -f "$PID_FILE"
    fi
fi

MODEL_REPO=$(resolve_model "$MODEL_ARG")

mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/server-${TIMESTAMP}.log"

echo "=== Starting MLX LLM Server ==="
echo "Host:   $HOST:$PORT"
echo "Model:  $MODEL_REPO"
echo "Log:    $LOG_FILE"
echo ""

# Start server in background
HF_HOME="$HF_HOME" nohup python3 -m mlx_lm.server \
    --host "$HOST" \
    --port "$PORT" \
    --model "$MODEL_REPO" \
    >> "$LOG_FILE" 2>&1 &

SERVER_PID=$!
echo "$SERVER_PID" > "$PID_FILE"

# Keep a symlink to the current log for easy tailing
ln -sf "$LOG_FILE" "$LOG_DIR/server-current.log"

echo "Server started (PID: $SERVER_PID)"
echo "Waiting for server to be ready..."
echo "(Model loading may take 1-3 minutes for large models)"
echo ""

MAX_WAIT=180
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -sf "http://localhost:$PORT/v1/models" > /dev/null 2>&1; then
        echo ""
        echo "✓ Server is ready at http://localhost:$PORT"
        echo ""
        echo "Quick test:"
        echo "  curl http://localhost:$PORT/v1/models"
        echo "  ./scripts/health-check.sh"
        exit 0
    fi
    # Check the process is still alive
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo ""
        echo "ERROR: Server process died. Check logs:"
        echo "  tail -50 $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
    sleep 3
    WAITED=$((WAITED + 3))
    printf "."
done

echo ""
echo "WARNING: Server did not respond within ${MAX_WAIT}s (still loading model?)"
echo "Check: tail -f $LOG_DIR/server-current.log"
