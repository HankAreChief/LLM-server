#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== LLM-server installation ==="
echo "Project: $PROJECT_DIR"
echo ""

# Create virtual environment
VENV="$PROJECT_DIR/.venv"
if [ ! -d "$VENV" ]; then
    echo "Creating Python virtual environment..."
    python3 -m venv "$VENV"
else
    echo "Virtual environment already exists."
fi

# Activate and install
source "$VENV/bin/activate"
echo "Installing Python dependencies..."
pip install --upgrade pip --quiet
pip install -r "$PROJECT_DIR/requirements.txt"

echo ""
echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. Download models:  ./scripts/download-models.sh --everyday-only"
echo "  2. Start server:     ./scripts/start-server.sh"
echo "  3. Health check:     ./scripts/health-check.sh"
