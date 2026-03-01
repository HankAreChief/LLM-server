#!/usr/bin/env bash
# start-instance.sh <alias>
# Starts a single mlx_lm.server instance bound to 127.0.0.1:<port>.
# Port and HF repo are read from config/models.json.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $(basename "$0") <model-alias>"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") glm-4.7-flash"
    echo "  $(basename "$0") qwen3-coder-moe"
    exit 1
}

[ "${1:-}" = "" ] && usage
ALIAS="$1"

# Load .env
[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"

# Activate venv
VENV="$PROJECT_DIR/.venv"
if [ -f "$VENV/bin/activate" ]; then
    source "$VENV/bin/activate"
else
    echo "ERROR: Virtual environment not found. Run ./scripts/install.sh first."
    exit 1
fi

# Read hf_repo and port from models.json via inline Python
read -r HF_REPO PORT < <(
    MODELS_JSON="$PROJECT_DIR/config/models.json" MODEL_ALIAS="$ALIAS" python3 - <<'PYEOF'
import json, os, sys
with open(os.environ['MODELS_JSON']) as f:
    data = json.load(f)
alias = os.environ['MODEL_ALIAS']
if alias not in data['fleet']:
    available = ', '.join(data['fleet'].keys())
    print(f"ERROR: Unknown alias '{alias}'.", file=sys.stderr)
    print(f"Available: {available}", file=sys.stderr)
    sys.exit(1)
cfg = data['fleet'][alias]
print(cfg['hf_repo'], cfg['port'])
PYEOF
)

PIDS_DIR="$PROJECT_DIR/logs/pids"
LOG_DIR="$PROJECT_DIR/logs"
PID_FILE="$PIDS_DIR/$ALIAS.pid"

mkdir -p "$PIDS_DIR" "$LOG_DIR"

# Check if already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Instance '$ALIAS' is already running (PID $OLD_PID, port $PORT)."
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/instance-${ALIAS}-${TIMESTAMP}.log"

echo "=== Starting instance: $ALIAS ==="
echo "  Repo:  $HF_REPO"
echo "  Port:  127.0.0.1:$PORT"
echo "  Log:   $LOG_FILE"
echo ""

HF_HOME="$HF_HOME" nohup python3 -m mlx_lm.server \
    --host 127.0.0.1 \
    --port "$PORT" \
    --model "$HF_REPO" \
    >> "$LOG_FILE" 2>&1 &

INSTANCE_PID=$!
echo "$INSTANCE_PID" > "$PID_FILE"

echo "Instance started (PID: $INSTANCE_PID)"
echo "Waiting for /health (max 180s)..."

MAX_WAIT=180
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -sf "http://127.0.0.1:$PORT/health" > /dev/null 2>&1; then
        echo ""
        echo "✓ Instance '$ALIAS' is ready at http://127.0.0.1:$PORT"
        exit 0
    fi
    if ! kill -0 "$INSTANCE_PID" 2>/dev/null; then
        echo ""
        echo "ERROR: Instance process died. Check logs:"
        echo "  tail -50 $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
    sleep 3
    WAITED=$((WAITED + 3))
    printf "."
done

echo ""
echo "WARNING: Instance '$ALIAS' did not respond within ${MAX_WAIT}s (still loading?)."
echo "Check: tail -f $LOG_FILE"
