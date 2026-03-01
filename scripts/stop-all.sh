#!/usr/bin/env bash
# stop-all.sh
# Stops the router first (no new requests), then all mlx_lm.server instances.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

PIDS_DIR="$PROJECT_DIR/logs/pids"

echo "=== Stopping all MLX LLM services ==="
echo ""

# 1. Stop router first
ROUTER_PID_FILE="$PIDS_DIR/router.pid"
if [ -f "$ROUTER_PID_FILE" ]; then
    ROUTER_PID=$(cat "$ROUTER_PID_FILE")
    if kill -0 "$ROUTER_PID" 2>/dev/null; then
        echo "Stopping router (PID $ROUTER_PID)..."
        kill -TERM "$ROUTER_PID"
        WAITED=0
        while [ $WAITED -lt 15 ]; do
            if ! kill -0 "$ROUTER_PID" 2>/dev/null; then
                break
            fi
            sleep 1
            WAITED=$((WAITED + 1))
        done
        if kill -0 "$ROUTER_PID" 2>/dev/null; then
            kill -9 "$ROUTER_PID" 2>/dev/null || true
        fi
    fi
    rm -f "$ROUTER_PID_FILE"
    echo "✓ Router stopped."
else
    echo "Router not running (no PID file)."
fi

echo ""

# 2. Stop all instances via stop-instance.sh
STOP_SCRIPT="$SCRIPT_DIR/stop-instance.sh"
FOUND_ANY=false

for PID_FILE in "$PIDS_DIR"/*.pid; do
    # glob may not expand if no files exist
    [ -e "$PID_FILE" ] || continue

    BASENAME="$(basename "$PID_FILE" .pid)"
    # Skip router (already handled)
    [ "$BASENAME" = "router" ] && continue

    FOUND_ANY=true
    bash "$STOP_SCRIPT" "$BASENAME"
done

if [ "$FOUND_ANY" = "false" ]; then
    echo "No instances running."
fi

echo ""
echo "✓ All services stopped."
