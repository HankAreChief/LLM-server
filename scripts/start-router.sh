#!/usr/bin/env bash
# start-router.sh
# Starts the FastAPI router/proxy (uvicorn router.proxy:app).
# Must be run from PROJECT_DIR so that the "router" Python package is on the path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load .env
[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
ROUTER_HOST="${ROUTER_HOST:-0.0.0.0}"
ROUTER_PORT="${ROUTER_PORT:-8080}"

PIDS_DIR="$PROJECT_DIR/logs/pids"
LOG_DIR="$PROJECT_DIR/logs"
PID_FILE="$PIDS_DIR/router.pid"

mkdir -p "$PIDS_DIR" "$LOG_DIR"

# Activate venv
VENV="$PROJECT_DIR/.venv"
if [ -f "$VENV/bin/activate" ]; then
    source "$VENV/bin/activate"
else
    echo "ERROR: Virtual environment not found. Run ./scripts/install.sh first."
    exit 1
fi

# Check if router is already running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Router is already running (PID $OLD_PID) on port $ROUTER_PORT."
        exit 0
    else
        rm -f "$PID_FILE"
    fi
fi

# Warn if port is already in use
if lsof -iTCP:"$ROUTER_PORT" -sTCP:LISTEN -P -n > /dev/null 2>&1; then
    echo "WARNING: Port $ROUTER_PORT is already in use."
    echo "If start-server.sh (single-model mode) is running, stop it first."
    echo "Cannot run single-model and multi-model modes simultaneously."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/router-${TIMESTAMP}.log"

echo "=== Starting MLX LLM Router ==="
echo "  Bind:  $ROUTER_HOST:$ROUTER_PORT"
echo "  Log:   $LOG_FILE"
echo ""

# Run uvicorn from PROJECT_DIR so "router.proxy" resolves as a package
cd "$PROJECT_DIR"
nohup uvicorn router.proxy:app \
    --host "$ROUTER_HOST" \
    --port "$ROUTER_PORT" \
    >> "$LOG_FILE" 2>&1 &

ROUTER_PID=$!
echo "$ROUTER_PID" > "$PID_FILE"

echo "Router started (PID: $ROUTER_PID)"
echo "Waiting for /health (max 30s)..."

MAX_WAIT=30
WAITED=0
while [ $WAITED -lt $MAX_WAIT ]; do
    if curl -sf "http://localhost:$ROUTER_PORT/health" > /dev/null 2>&1; then
        echo ""
        echo "✓ Router is ready at http://localhost:$ROUTER_PORT"
        echo ""
        echo "Next steps:"
        echo "  ./scripts/start-instance.sh glm-4.7-flash"
        echo "  curl http://localhost:$ROUTER_PORT/v1/models"
        exit 0
    fi
    if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
        echo ""
        echo "ERROR: Router process died. Check logs:"
        echo "  tail -50 $LOG_FILE"
        rm -f "$PID_FILE"
        exit 1
    fi
    sleep 1
    WAITED=$((WAITED + 1))
    printf "."
done

echo ""
echo "WARNING: Router did not respond within ${MAX_WAIT}s."
echo "Check: tail -f $LOG_FILE"
