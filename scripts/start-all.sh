#!/usr/bin/env bash
# start-all.sh
# Starts the router and all fleet instances.
# Instances are started in parallel; script exits once all have been launched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Starting full MLX LLM stack ==="
echo ""

# Start router (blocks until ready or fails)
bash "$SCRIPT_DIR/start-router.sh"

echo ""
echo "Starting all fleet instances in parallel..."
echo ""

ALIASES=(glm-4.7-flash deepseek-r1-14b devstral-24b qwen3-coder-moe qwen3-32b-dense llama-3.3-70b qwen3.5-397b)

for alias in "${ALIASES[@]}"; do
    bash "$SCRIPT_DIR/start-instance.sh" "$alias" \
        &> "$PROJECT_DIR/logs/startlog-${alias}.txt" &
done

echo "All ${#ALIASES[@]} instances launching in background."
echo "Check status: curl http://localhost:8080/health"
echo "Check logs:   tail -f logs/startlog-<alias>.txt"
