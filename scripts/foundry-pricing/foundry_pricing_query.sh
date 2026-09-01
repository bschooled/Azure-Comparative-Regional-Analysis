#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PYTHON_SCRIPT="${SCRIPT_DIR}/python/foundry_pricing_query.py"

if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
  exec python3 "$PYTHON_SCRIPT" "$@"
fi

if command -v python >/dev/null 2>&1 && python -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
  exec python "$PYTHON_SCRIPT" "$@"
fi

echo "Python 3.10 or newer is required." >&2
echo "macOS: install with 'brew install python' or use the Python installer from python.org." >&2
exit 1
