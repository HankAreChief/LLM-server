#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_JSON="$PROJECT_DIR/config/models.json"

# Download order: smallest to largest
DOWNLOAD_ORDER="glm-4.7-flash deepseek-r1-14b devstral-24b qwen3-coder-moe qwen3-32b-dense llama-3.3-70b qwen3.5-397b"

EVERYDAY_ONLY=false
SINGLE_MODEL=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  --everyday-only     Skip heavyweight models (category: heavyweight)
  --model <alias>     Download a single model by alias
  -h, --help          Show this help

Note: Heavyweight models (e.g. qwen3.5-397b, ~223GB) are only downloaded
      when explicitly requested with --model, never by default.

Examples:
  $(basename "$0") --everyday-only          # Download all everyday models (~100GB)
  $(basename "$0") --model glm-4.7-flash    # Download a single model
  $(basename "$0") --model qwen3.5-397b     # Download the heavyweight model
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --everyday-only) EVERYDAY_ONLY=true; shift ;;
        --model) SINGLE_MODEL="${2:-}"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
done

# Load .env
[ -f "$PROJECT_DIR/.env" ] && source "$PROJECT_DIR/.env"
HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"

# Activate venv
VENV="$PROJECT_DIR/.venv"
if [ -f "$VENV/bin/activate" ]; then
    source "$VENV/bin/activate"
else
    echo "ERROR: Virtual environment not found. Run ./scripts/install.sh first."
    exit 1
fi

# Build list of models to download
MODELS_TO_DOWNLOAD=$(
    MODELS_JSON="$MODELS_JSON" \
    EVERYDAY_ONLY="$EVERYDAY_ONLY" \
    SINGLE_MODEL="$SINGLE_MODEL" \
    DOWNLOAD_ORDER="$DOWNLOAD_ORDER" \
    python3 << 'PYEOF'
import json, os, sys

models_json  = os.environ['MODELS_JSON']
everyday_only = os.environ['EVERYDAY_ONLY'] == 'true'
single_model  = os.environ.get('SINGLE_MODEL', '').strip()
download_order = os.environ['DOWNLOAD_ORDER'].split()

with open(models_json) as f:
    data = json.load(f)

fleet = data['fleet']

if single_model:
    if single_model not in fleet:
        available = ', '.join(fleet.keys())
        print(f"ERROR: Model '{single_model}' not found.", file=sys.stderr)
        print(f"Available aliases: {available}", file=sys.stderr)
        sys.exit(1)
    m = fleet[single_model]
    print(f"{single_model}|{m['hf_repo']}|{m['size_gb']}|{m['category']}|{m['role']}")
else:
    for alias in download_order:
        if alias not in fleet:
            continue
        m = fleet[alias]
        # Heavyweight models require explicit --model flag
        if m['category'] == 'heavyweight':
            continue
        print(f"{alias}|{m['hf_repo']}|{m['size_gb']}|{m['category']}|{m['role']}")
PYEOF
)

if [ -z "$MODELS_TO_DOWNLOAD" ]; then
    echo "No models to download."
    exit 0
fi

# Calculate total size
TOTAL_GB=$(echo "$MODELS_TO_DOWNLOAD" | awk -F'|' '{sum += $3} END {print sum}')

echo "=== MLX Model Downloader ==="
echo "Cache: $HF_HOME"
echo "Total download: ~${TOTAL_GB} GB"
echo ""

# Check available disk space
mkdir -p "$HF_HOME"
AVAILABLE_GB=$(df -g "$HF_HOME" | awk 'NR==2{print $4}')
echo "Disk available: ~${AVAILABLE_GB} GB"

if [ "$AVAILABLE_GB" -lt "$TOTAL_GB" ]; then
    echo ""
    echo "WARNING: Need ~${TOTAL_GB}GB but only ~${AVAILABLE_GB}GB available."
    read -rp "Continue anyway? [y/N] " yn
    [[ "$yn" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi
echo ""

# Download each model
COUNT=0
TOTAL=$(echo "$MODELS_TO_DOWNLOAD" | wc -l | tr -d ' ')

while IFS='|' read -r alias hf_repo size_gb category role; do
    COUNT=$((COUNT + 1))
    echo "══════════════════════════════════════════════════════════"
    echo "[$COUNT/$TOTAL] $alias"
    echo "        Role: $role"
    echo "        Repo: $hf_repo"
    echo "        Size: ~${size_gb} GB  |  Category: $category"
    echo ""

    HF_HOME="$HF_HOME" hf download "$hf_repo" --repo-type model

    echo ""
    echo "✓ $alias downloaded successfully"
    echo ""
done <<< "$MODELS_TO_DOWNLOAD"

echo "══════════════════════════════════════════════════════════"
echo "All downloads complete."
echo ""
echo "Start server: ./scripts/start-server.sh"
