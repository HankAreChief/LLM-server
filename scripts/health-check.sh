#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
PORT="${MLX_SERVER_PORT:-8080}"
ENDPOINT="http://localhost:$PORT/v1/models"

RESPONSE=$(curl -sf --max-time 5 "$ENDPOINT" 2>/dev/null) || {
    echo "✗ Server not responding at $ENDPOINT"
    exit 1
}

echo "✓ Server is healthy at $ENDPOINT"
echo ""

echo "$RESPONSE" | python3 -c "
import json, sys
data = json.load(sys.stdin)
models = data.get('data', [])
if models:
    print('Loaded model(s):')
    for m in models:
        print(f'  - {m[\"id\"]}')
else:
    print('No models reported')
"
exit 0
