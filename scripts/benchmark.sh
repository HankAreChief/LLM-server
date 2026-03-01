#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
PORT="${MLX_SERVER_PORT:-8080}"
LOG_DIR="$PROJECT_DIR/logs"

PROMPT="${1:-Explain the difference between transformers and state space models in three concise paragraphs.}"

echo "=== MLX Server Benchmark ==="
echo "Endpoint: http://localhost:$PORT"
echo "Prompt:   $PROMPT"
echo ""

# Check server is up
curl -sf "http://localhost:$PORT/v1/models" > /dev/null 2>&1 || {
    echo "ERROR: Server not running. Start with: ./scripts/start-server.sh"
    exit 1
}

# Get current model
CURRENT_MODEL=$(curl -sf "http://localhost:$PORT/v1/models" | python3 -c "
import json, sys
d = json.load(sys.stdin)
models = d.get('data', [])
print(models[0]['id'] if models else 'unknown')
")

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
SAFE_MODEL="${CURRENT_MODEL//\//_}"
RESULT_FILE="$LOG_DIR/benchmark-${SAFE_MODEL}-${TIMESTAMP}.json"

echo "Model:    $CURRENT_MODEL"
echo ""
echo "─────────────────────────────────────────────────────────"

# Run streaming benchmark via Python
ENDPOINT="http://localhost:$PORT/v1/chat/completions" \
PROMPT="$PROMPT" \
CURRENT_MODEL="$CURRENT_MODEL" \
RESULT_FILE="$RESULT_FILE" \
TIMESTAMP="$TIMESTAMP" \
python3 << 'PYEOF'
import json, time, sys, os
import urllib.request, urllib.error

endpoint     = os.environ['ENDPOINT']
prompt       = os.environ['PROMPT']
model        = os.environ['CURRENT_MODEL']
result_file  = os.environ['RESULT_FILE']
timestamp    = os.environ['TIMESTAMP']

payload = json.dumps({
    "model": model,
    "messages": [{"role": "user", "content": prompt}],
    "stream": True,
    "max_tokens": 4096,
}).encode()

req = urllib.request.Request(
    endpoint,
    data=payload,
    headers={"Content-Type": "application/json"},
)

start_time            = time.time()
first_token_time      = None  # first token of any kind (reasoning or content)
first_content_time    = None  # first actual content token
reasoning_tokens      = 0
content_tokens        = 0
reasoning_text        = ""
content_text          = ""

try:
    with urllib.request.urlopen(req, timeout=120) as resp:
        for raw_line in resp:
            line = raw_line.decode("utf-8").strip()
            if not line.startswith("data: "):
                continue
            data = line[6:]
            if data == "[DONE]":
                break
            try:
                chunk = json.loads(data)
                delta = chunk.get("choices", [{}])[0].get("delta", {})

                reasoning = delta.get("reasoning", "")
                content   = delta.get("content", "")

                if reasoning:
                    if first_token_time is None:
                        first_token_time = time.time()
                    reasoning_tokens += 1
                    reasoning_text   += reasoning

                if content:
                    if first_token_time is None:
                        first_token_time = time.time()
                    if first_content_time is None:
                        first_content_time = time.time()
                    content_tokens += 1
                    content_text   += content
                    print(content, end="", flush=True)

            except json.JSONDecodeError:
                pass
except urllib.error.URLError as e:
    print(f"\nERROR: {e}", file=sys.stderr)
    sys.exit(1)

end_time   = time.time()
total_time = end_time - start_time
print("\n─────────────────────────────────────────────────────────")

if first_token_time is None:
    print("ERROR: No tokens received from server.", file=sys.stderr)
    sys.exit(1)

total_tokens    = reasoning_tokens + content_tokens
ttft            = first_token_time - start_time
generation_time = end_time - first_token_time
tps             = total_tokens / generation_time if generation_time > 0 else 0
# Content-only tok/s (excluding thinking phase)
content_tps     = content_tokens / (end_time - first_content_time) if first_content_time else 0

is_thinking = reasoning_tokens > 0

print(f"\n=== Results ===")
print(f"Model:               {model}")
if is_thinking:
    print(f"Thinking tokens:     {reasoning_tokens}")
    print(f"Content tokens:      {content_tokens}")
else:
    print(f"Tokens generated:    {content_tokens}")
print(f"Time to first token: {ttft:.2f}s")
if is_thinking and first_content_time:
    print(f"Time to first content: {first_content_time - start_time:.2f}s")
print(f"Generation time:     {generation_time:.2f}s")
print(f"Total time:          {total_time:.2f}s")
print(f"Tokens / second:     {tps:.1f} tok/s (total)")
if is_thinking:
    print(f"Content tok/s:       {content_tps:.1f} tok/s")

os.makedirs(os.path.dirname(result_file), exist_ok=True)
results = {
    "model":            model,
    "prompt":           prompt,
    "thinking_model":   is_thinking,
    "reasoning_tokens": reasoning_tokens,
    "content_tokens":   content_tokens,
    "total_tokens":     total_tokens,
    "ttft_s":           round(ttft, 3),
    "total_s":          round(total_time, 3),
    "tps":              round(tps, 1),
    "content_tps":      round(content_tps, 1),
    "timestamp":        timestamp,
}
with open(result_file, "w") as f:
    json.dump(results, f, indent=2, ensure_ascii=False)
print(f"\nSaved: {result_file}")
PYEOF
