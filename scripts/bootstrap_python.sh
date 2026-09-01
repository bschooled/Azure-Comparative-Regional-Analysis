#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://packagefeedproxy.microsoft.io/pypi/simple}"

cd "$PROJECT_ROOT"

python3 -m venv .venv
.venv/bin/pip install --index-url "$PIP_INDEX_URL" --upgrade pip
.venv/bin/pip install --index-url "$PIP_INDEX_URL" -e .

echo "Python environment ready at $PROJECT_ROOT/.venv"
echo "Use: .venv/bin/python -m azure_compare_cli --help"