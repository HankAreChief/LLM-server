# LLM-server — Local MLX Inference on Mac Studio M3 Ultra

Local LLM inference server running on **Mac Studio M3 Ultra (512 GB unified memory)**.
Models are served via Apple's [MLX](https://github.com/ml-explore/mlx) framework through an
**OpenAI-compatible REST API**, accessible to OpenClaw clients on the local network.

Two operating modes:

| Mode | Script | Description |
|---|---|---|
| **Single-model** | `start-server.sh` | One model at a time, hot-swap via `switch-model.sh` |
| **Multi-model** | `start-router.sh` + `start-instance.sh` | Several models loaded simultaneously, routed by `model` field |

> Port 8080 is shared — the two modes cannot run at the same time.

---

## Quick Start — Single-model mode

```bash
# 1. Install dependencies
./scripts/install.sh

# 2. Download everyday models (~100 GB)
./scripts/download-models.sh --everyday-only

# 3. Start the server (default model from .env)
./scripts/start-server.sh

# 4. Verify
./scripts/health-check.sh
```

## Quick Start — Multi-model mode

```bash
# 1. Install dependencies (same as above)
./scripts/install.sh

# 2. Start the router (FastAPI proxy on :8080)
./scripts/start-router.sh

# 3. Start individual model instances
./scripts/start-instance.sh glm-4.7-flash
./scripts/start-instance.sh qwen3-coder-moe

# 4. Verify
curl http://localhost:8080/health
curl http://localhost:8080/v1/models

# 5. Stop everything
./scripts/stop-all.sh
```

---

## Available Models

| Alias | Port | HF Repo | Size | Role | Category |
|---|---|---|---|---|---|
| `glm-4.7-flash` | 8081 | mlx-community/GLM-4.7-Flash-4bit | ~3 GB | Fast replies, heartbeats | everyday |
| `deepseek-r1-14b` | 8082 | mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit | ~9 GB | Deep reasoning | everyday |
| `devstral-24b` | 8083 | mlx-community/mistralai_Devstral-Small-2-24B-Instruct-2512-MLX-4Bit | ~14 GB | Coding backup (Mistral) | everyday |
| `qwen3-coder-moe` | 8084 | mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit | ~17 GB | Primary coder (MoE, 3B active) | everyday |
| `qwen3-32b-dense` | 8085 | mlx-community/Qwen3-32B-4bit | ~18 GB | General coding / reasoning | everyday |
| `llama-3.3-70b` | 8086 | mlx-community/Llama-3.3-70B-Instruct-4bit | ~39 GB | General reasoning, writing | everyday |
| `qwen3.5-397b` | 8087 | mlx-community/Qwen3.5-397B-A17B-nvfp4 | ~223 GB | Frontier-class (MoE, 17B active) | heavyweight |

> **Note:** The heavyweight model must be downloaded explicitly:
> `./scripts/download-models.sh --model qwen3.5-397b`

---

## Memory Budget

| Item | Size |
|---|---|
| GLM-4.7 Flash 4bit | ~3 GB |
| DeepSeek-R1-Distill-14B 4bit | ~9 GB |
| Devstral-24B 4bit | ~14 GB |
| Qwen3-Coder-30B-A3B 4bit | ~17 GB |
| Qwen3-32B dense 4bit | ~18 GB |
| Llama 3.3 70B 4bit | ~39 GB |
| **Everyday fleet total** | **~100 GB** |
| Qwen3.5-397B nvfp4 | ~223 GB |
| macOS + overhead | ~30 GB |
| **Total (everything loaded)** | **~353 GB** |
| **Headroom for context** | **~159 GB** |

In multi-model mode all started instances are resident in memory simultaneously.
The M3 Ultra's 512 GB unified memory comfortably fits the entire everyday fleet (~100 GB)
or any combination that stays within the headroom above.

---

## Scripts

| Script | Description |
|---|---|
| `scripts/install.sh` | Create venv and install Python dependencies |
| `scripts/download-models.sh` | Download models from HuggingFace |
| `scripts/start-server.sh` | Start single-model MLX inference server |
| `scripts/switch-model.sh` | Hot-swap to a different model (single-model mode) |
| `scripts/health-check.sh` | Verify the server is responding |
| `scripts/benchmark.sh` | Measure TTFT and tokens/second |
| `scripts/start-router.sh` | Start the FastAPI multi-model router on :8080 |
| `scripts/start-instance.sh` | Start one mlx_lm.server instance on its dedicated port |
| `scripts/stop-instance.sh` | Gracefully stop one instance |
| `scripts/stop-all.sh` | Stop router then all instances |

### Downloading models

```bash
./scripts/download-models.sh --everyday-only          # All everyday models
./scripts/download-models.sh --model glm-4.7-flash    # Single model by alias
./scripts/download-models.sh --model qwen3.5-397b     # The heavyweight model
```

### Single-model mode

```bash
./scripts/start-server.sh                                      # Default model (.env)
./scripts/start-server.sh --model llama-3.3-70b               # By alias
./scripts/start-server.sh --model mlx-community/Qwen3-32B-4bit  # Direct HF repo

./scripts/switch-model.sh deepseek-r1-14b    # Hot-swap to reasoning model
./scripts/switch-model.sh glm-4.7-flash      # Switch back to fast model
```

### Multi-model mode

```bash
# Start router (once)
./scripts/start-router.sh

# Start whichever instances you need
./scripts/start-instance.sh glm-4.7-flash
./scripts/start-instance.sh qwen3-coder-moe
./scripts/start-instance.sh llama-3.3-70b

# Stop one instance
./scripts/stop-instance.sh llama-3.3-70b

# Stop everything
./scripts/stop-all.sh
```

Each instance binds to `127.0.0.1:<port>` (not externally visible).
The router binds to `0.0.0.0:8080` and forwards requests based on the `model` field.

### Benchmarking

```bash
./scripts/benchmark.sh                                 # Default prompt
./scripts/benchmark.sh "Write a sort function in Rust" # Custom prompt
```

---

## API Endpoints

The server (both modes) exposes an **OpenAI-compatible API** on `http://<server-ip>:8080`.

### Health

```bash
curl http://localhost:8080/health
```

In multi-model mode this also reports which instances are currently running:

```json
{
  "status": "ok",
  "router": "running",
  "fleet_total": 7,
  "instances_running": 2,
  "running": ["glm-4.7-flash", "qwen3-coder-moe"]
}
```

### List models

```bash
curl http://localhost:8080/v1/models
```

In multi-model mode only **running** instances are returned (PID-based, not HF cache).

### Chat completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "glm-4.7-flash",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

The `model` field accepts either the alias (`glm-4.7-flash`) or the full HF repo name
(`mlx-community/GLM-4.7-Flash-4bit`) — both are resolved to the correct instance.

### Streaming chat completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-coder-moe",
    "messages": [{"role": "user", "content": "Write a Python quicksort."}],
    "stream": true
  }'
```

### Error responses

| HTTP | Condition |
|---|---|
| 404 | `model` field not in fleet — response includes list of valid aliases |
| 503 | Model known but instance not started — response includes the `start-instance.sh` command to run |
| 503 | Instance crashed after startup check (TOCTOU) |

---

## OpenClaw Client Configuration

OpenClaw clients on the same network should point to:

```
Base URL:  http://<mac-studio-ip>:8080/v1
API Key:   (any non-empty string — not validated)
Model:     glm-4.7-flash   (or whichever alias is running)
```

Find the Mac Studio's IP:

```bash
ipconfig getifaddr en0    # Ethernet
ipconfig getifaddr en1    # Wi-Fi
```

> The router (and single-model server) listen on `0.0.0.0:8080` — any device on the
> local network can reach it. No authentication is enforced — keep it on a trusted LAN.

---

## Configuration Files

### `.env`

```env
MLX_SERVER_HOST=0.0.0.0
MLX_SERVER_PORT=8080
HF_HOME=/Users/hank/.cache/huggingface
DEFAULT_MODEL=mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit

# Multi-model router
ROUTER_HOST=0.0.0.0
ROUTER_PORT=8080
```

### `config/models.json`

Registry of all models with metadata (alias, HF repo, port, size, role).
Used by all scripts. Add new models here to make them available.

---

## Logs

```bash
# Single-model mode
tail -f logs/server-current.log

# Multi-model mode
tail -f logs/router-*.log
tail -f logs/instance-glm-4.7-flash-*.log

# Benchmarks
ls logs/benchmark-*.json
```

PID files live in `logs/pids/`:
- `logs/pids/router.pid`
- `logs/pids/<alias>.pid`

---

## Troubleshooting

**Router/instance won't start**
```bash
tail -50 logs/router-*.log
tail -50 logs/instance-<alias>-*.log
```
Common causes: model not downloaded, port already in use, venv not activated.

**Port 8080 already in use when starting router**

`start-router.sh` will warn you. Either `start-server.sh` (single-model mode) is running,
or a previous router wasn't shut down cleanly:
```bash
./scripts/stop-all.sh
# or manually:
cat logs/pids/router.pid | xargs kill
```

**`mlx_lm` not found**
```bash
./scripts/install.sh    # Re-run installation
```

**Model alias not recognised**
```bash
cat config/models.json | python3 -c "import json,sys; [print(k) for k in json.load(sys.stdin)['fleet']]"
```

**Server responds but model output is garbled**
Ensure the model was fully downloaded:
```bash
huggingface-cli scan-cache
```

**Server doesn't respond from another machine**
- Confirm `ROUTER_HOST=0.0.0.0` (or `MLX_SERVER_HOST=0.0.0.0`) in `.env`
- Check macOS firewall: System Settings → Network → Firewall
- Verify port: `lsof -i :8080`

**Kill a stuck process manually**
```bash
# Router
cat logs/pids/router.pid | xargs kill && rm logs/pids/router.pid

# Instance
cat logs/pids/glm-4.7-flash.pid | xargs kill && rm logs/pids/glm-4.7-flash.pid
```
