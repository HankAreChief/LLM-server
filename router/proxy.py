"""
FastAPI router/proxy for multi-instance MLX LLM server.

Routes POST /v1/chat/completions to the correct mlx_lm.server instance
based on the "model" field in the request body.
"""

import json
import os
from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse

# ---------------------------------------------------------------------------
# Config loading (module-level, fails fast if models.json is missing/corrupt)
# ---------------------------------------------------------------------------

_PROJECT_DIR = Path(__file__).parent.parent
_MODELS_JSON = _PROJECT_DIR / "config" / "models.json"
_PIDS_DIR = _PROJECT_DIR / "logs" / "pids"

with open(_MODELS_JSON) as _f:
    _data = json.load(_f)

FLEET: dict = _data["fleet"]  # alias -> cfg dict

# alias -> cfg  (primary lookup)
ALIAS_MAP: dict = FLEET

# hf_repo -> alias  (fallback lookup when client sends the full repo name)
REPO_MAP: dict = {cfg["hf_repo"]: alias for alias, cfg in FLEET.items()}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _resolve_alias(model_field: str) -> str | None:
    """Return canonical alias for a model field value, or None if unknown."""
    if model_field in ALIAS_MAP:
        return model_field
    if model_field in REPO_MAP:
        return REPO_MAP[model_field]
    return None


def _pid_alive(alias: str) -> bool:
    """Return True if the instance for *alias* has a live PID file."""
    pid_file = _PIDS_DIR / f"{alias}.pid"
    if not pid_file.exists():
        return False
    try:
        pid = int(pid_file.read_text().strip())
        os.kill(pid, 0)  # signal 0: existence check only
        return True
    except (ValueError, ProcessLookupError, PermissionError):
        return False


# ---------------------------------------------------------------------------
# Shared HTTP client via FastAPI lifespan
# ---------------------------------------------------------------------------

_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global _client
    _client = httpx.AsyncClient(timeout=httpx.Timeout(connect=5.0, read=300.0, write=30.0, pool=5.0))
    yield
    await _client.aclose()


app = FastAPI(title="MLX LLM Router", version="1.0.0", lifespan=lifespan)


# ---------------------------------------------------------------------------
# Exception handler: upstream unreachable
# ---------------------------------------------------------------------------

@app.exception_handler(httpx.ConnectError)
async def connect_error_handler(request: Request, exc: httpx.ConnectError):
    return JSONResponse(
        status_code=503,
        content={"error": {"message": "Instance unreachable — it may have crashed after startup check.", "type": "service_unavailable"}},
    )


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    running = [alias for alias in FLEET if _pid_alive(alias)]
    return {
        "status": "ok",
        "router": "running",
        "fleet_total": len(FLEET),
        "instances_running": len(running),
        "running": running,
    }


@app.get("/v1/models")
async def list_models():
    """Return only currently running instances (PID-based, not HF-cache)."""
    models = []
    for alias, cfg in FLEET.items():
        if _pid_alive(alias):
            models.append({
                "id": alias,
                "object": "model",
                "owned_by": "mlx-community",
                "hf_repo": cfg["hf_repo"],
                "port": cfg["port"],
            })
    return {"object": "list", "data": models}


@app.post("/v1/chat/completions")
async def chat_completions(request: Request):
    body = await request.json()
    model_field: str = body.get("model", "")

    alias = _resolve_alias(model_field)
    if alias is None:
        available = list(FLEET.keys())
        return JSONResponse(
            status_code=404,
            content={
                "error": {
                    "message": f"Unknown model '{model_field}'. Available aliases: {available}",
                    "type": "invalid_request_error",
                }
            },
        )

    if not _pid_alive(alias):
        cfg = FLEET[alias]
        return JSONResponse(
            status_code=503,
            content={
                "error": {
                    "message": (
                        f"Model '{alias}' is not running. "
                        f"Start it with: ./scripts/start-instance.sh {alias}"
                    ),
                    "type": "service_unavailable",
                }
            },
        )

    port = FLEET[alias]["port"]
    url = f"http://127.0.0.1:{port}/v1/chat/completions"

    is_streaming = body.get("stream", False)

    if is_streaming:
        async def stream_generator():
            async with _client.stream("POST", url, json=body) as resp:
                async for chunk in resp.aiter_bytes():
                    yield chunk

        return StreamingResponse(
            stream_generator(),
            media_type="text/event-stream",
            headers={
                "X-Accel-Buffering": "no",
                "Cache-Control": "no-cache",
            },
        )
    else:
        resp = await _client.post(url, json=body)
        return JSONResponse(status_code=resp.status_code, content=resp.json())
