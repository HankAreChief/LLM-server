# LLM-server — Local MLX Inference on Mac Studio M3 Ultra

Local LLM inference server running on **Mac Studio M3 Ultra (512 GB unified memory)**.
Models are served via Apple's [MLX](https://github.com/ml-explore/mlx) framework through an
**OpenAI-compatible REST API**, accessible to OpenClaw clients on the local network.

---

## Quick Start

```bash
# 1. Install dependencies
./scripts/install.sh

# 2. Download everyday models (~100 GB, takes a few hours)
./scripts/download-models.sh --everyday-only

# 3. Start the server (default model from .env)
./scripts/start-server.sh

# 4. Verify
./scripts/health-check.sh
```

---

## Available Models

| Alias | HF Repo | Size | Role | Category |
|---|---|---|---|---|
| `glm-4.7-flash` | mlx-community/GLM-4.7-Flash-4bit | ~3 GB | Fast replies, heartbeats | everyday |
| `deepseek-r1-14b` | mlx-community/DeepSeek-R1-Distill-Qwen-14B-4bit | ~9 GB | Deep reasoning | everyday |
| `devstral-24b` | mlx-community/mistralai_Devstral-Small-2-24B-Instruct-2512-MLX-4Bit | ~14 GB | Coding backup (Mistral) | everyday |
| `qwen3-coder-moe` | mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit | ~17 GB | Primary coder (MoE, 3B active) | everyday |
| `qwen3-32b-dense` | mlx-community/Qwen3-32B-4bit | ~18 GB | General coding / reasoning | everyday |
| `llama-3.3-70b` | mlx-community/Llama-3.3-70B-Instruct-4bit | ~39 GB | General reasoning, writing | everyday |
| `qwen3.5-397b` | mlx-community/Qwen3.5-397B-A17B-nvfp4 | ~223 GB | Frontier-class (MoE, 17B active) | heavyweight |

> **Note:** The heavyweight model (`qwen3.5-397b`) must be downloaded explicitly:
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

`mlx_lm.server` loads one model at a time. The above figures reflect disk/VRAM when
that single model is active.

---

## Scripts

| Script | Description |
|---|---|
| `scripts/install.sh` | Create venv and install Python dependencies |
| `scripts/download-models.sh` | Download models from HuggingFace |
| `scripts/start-server.sh` | Start the MLX inference server |
| `scripts/switch-model.sh` | Hot-swap to a different model |
| `scripts/health-check.sh` | Verify the server is responding |
| `scripts/benchmark.sh` | Measure TTFT and tokens/second |

### Downloading models

```bash
./scripts/download-models.sh --everyday-only          # All everyday models
./scripts/download-models.sh --model glm-4.7-flash    # Single model by alias
./scripts/download-models.sh --model qwen3.5-397b     # The heavyweight model
```

### Starting the server

```bash
./scripts/start-server.sh                                      # Default model (.env)
./scripts/start-server.sh --model llama-3.3-70b               # By alias
./scripts/start-server.sh --model mlx-community/Qwen3-32B-4bit  # Direct HF repo
```

### Switching models

```bash
./scripts/switch-model.sh deepseek-r1-14b    # Switch to reasoning model
./scripts/switch-model.sh glm-4.7-flash      # Switch back to fast model
```

### Benchmarking

```bash
./scripts/benchmark.sh                         # Default prompt
./scripts/benchmark.sh "Write a sort function in Rust"   # Custom prompt
```

---

## API Endpoints

The server exposes an **OpenAI-compatible API** on `http://<server-ip>:8080`.

### List models

```bash
curl http://localhost:8080/v1/models
```

### Chat completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "default",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Streaming chat completion

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "default",
    "messages": [{"role": "user", "content": "Write a Python quicksort."}],
    "stream": true
  }'
```

---

## OpenClaw Client Configuration

OpenClaw clients on the same network should point to:

```
Base URL:  http://<mac-studio-ip>:8080/v1
API Key:   (any non-empty string — not validated)
Model:     default
```

Find the Mac Studio's IP:

```bash
ipconfig getifaddr en0    # Ethernet
ipconfig getifaddr en1    # Wi-Fi
```

Example full URL: `http://192.168.1.42:8080/v1/chat/completions`

> The server listens on `0.0.0.0:8080` (all interfaces) so any device on
> the local network can reach it. No authentication is enforced — keep it
> on a trusted LAN.

---

## Configuration Files

### `.env`

```env
MLX_SERVER_HOST=0.0.0.0
MLX_SERVER_PORT=8080
HF_HOME=/Users/hank/.cache/huggingface
DEFAULT_MODEL=mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit
```

### `config/models.json`

Registry of all models with metadata. Used by download and start scripts.
Add new models here to make them available via alias.

---

## Logs

```bash
tail -f logs/server-current.log    # Live server log
ls logs/benchmark-*.json           # Past benchmark results
```

---

## Troubleshooting

**Server won't start / crashes immediately**
```bash
tail -50 logs/server-current.log
```
Common causes: model not downloaded, insufficient memory, venv not activated.

**`mlx_lm` not found**
```bash
./scripts/install.sh    # Re-run installation
```

**Model alias not recognised**
```bash
cat config/models.json | python3 -c "import json,sys; [print(k) for k in json.load(sys.stdin)['fleet']]"
```

**Server responds but model output is garbled**
Try a smaller quantisation or ensure the model was fully downloaded:
```bash
huggingface-cli scan-cache
```

**Server doesn't respond from another machine**
- Confirm `MLX_SERVER_HOST=0.0.0.0` in `.env`
- Check macOS firewall: System Settings → Network → Firewall
- Verify port: `lsof -i :8080`

**Kill a stuck server manually**
```bash
cat logs/server.pid | xargs kill
rm logs/server.pid
```
