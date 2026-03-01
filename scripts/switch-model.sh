#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
PORT="${MLX_SERVER_PORT:-8080}"
PID_FILE="$PROJECT_DIR/logs/server.pid"

usage() {
    cat <<EOF
Usage: $(basename "$0") <model-alias>

Stops the running server and starts it with a new model.

Examples:
  $(basename "$0") glm-4.7-flash
  $(basename "$0") qwen3-coder-moe
  $(basename "$0") qwen3.5-397b
EOF
    exit 1
}

[ $# -lt 1 ] && usage
MODEL="$1"

echo "=== Switching model to: $MODEL ==="
echo ""

# Stop existing server
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Stopping current server (PID $OLD_PID)..."
        kill "$OLD_PID"

        WAITED=0
        printf "Waiting for shutdown"
        while kill -0 "$OLD_PID" 2>/dev/null && [ $WAITED -lt 30 ]; do
            sleep 1
            WAITED=$((WAITED + 1))
            printf "."
        done
        echo ""

        if kill -0 "$OLD_PID" 2>/dev/null; then
            echo "Server did not stop gracefully, forcing..."
            kill -9 "$OLD_PID" 2>/dev/null || true
            sleep 1
        fi

        echo "✓ Server stopped"
    else
        echo "PID $OLD_PID not running (stale PID file)."
    fi
    rm -f "$PID_FILE"
else
    echo "No running server found (no PID file)."
fi

echo ""

# Start server with new model
"$SCRIPT_DIR/start-server.sh" --model "$MODEL"
