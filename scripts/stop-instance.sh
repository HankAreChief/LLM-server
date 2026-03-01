#!/usr/bin/env bash
# stop-instance.sh <alias>
# Gracefully stops a running mlx_lm.server instance.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $(basename "$0") <model-alias>"
    exit 1
}

[ "${1:-}" = "" ] && usage
ALIAS="$1"

PIDS_DIR="$PROJECT_DIR/logs/pids"
PID_FILE="$PIDS_DIR/$ALIAS.pid"

if [ ! -f "$PID_FILE" ]; then
    echo "No PID file for '$ALIAS' — instance may not be running."
    exit 0
fi

PID=$(cat "$PID_FILE")

if ! kill -0 "$PID" 2>/dev/null; then
    echo "Instance '$ALIAS' (PID $PID) is not running. Removing stale PID file."
    rm -f "$PID_FILE"
    exit 0
fi

echo "Stopping instance '$ALIAS' (PID $PID)..."
kill -TERM "$PID"

# Wait up to 30s for graceful shutdown
WAITED=0
while [ $WAITED -lt 30 ]; do
    if ! kill -0 "$PID" 2>/dev/null; then
        rm -f "$PID_FILE"
        echo "✓ Instance '$ALIAS' stopped."
        exit 0
    fi
    sleep 1
    WAITED=$((WAITED + 1))
done

# Force kill
echo "Graceful shutdown timed out — sending SIGKILL to PID $PID"
kill -9 "$PID" 2>/dev/null || true
rm -f "$PID_FILE"
echo "✓ Instance '$ALIAS' killed."
