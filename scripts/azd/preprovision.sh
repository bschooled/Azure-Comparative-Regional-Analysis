#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "[azd hook] preprovision: preparing azd environment and auth prerequisites"

resource_group="${AZURE_RESOURCE_GROUP:-}"
environment_name="${AZURE_ENV_NAME:-}"
if [[ -z "$resource_group" ]]; then
  resource_group="$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || true)"
fi
if [[ -z "$environment_name" ]]; then
  environment_name="$(azd env get-value AZURE_ENV_NAME 2>/dev/null || true)"
fi

if [[ -z "$resource_group" ]]; then
  echo "AZURE_RESOURCE_GROUP is not set. Run 'azd env set AZURE_RESOURCE_GROUP <name>' before provisioning." >&2
  exit 1
fi

helper_args=(--resource-group "$resource_group")
if [[ -n "$environment_name" ]]; then
  helper_args+=(--environment-name "$environment_name")
fi

exec "$PROJECT_ROOT/scripts/deploy_azure_pipeline.sh" \
  "${helper_args[@]}" \
  --create-web-auth-app \
  --create-function-auth-app \
  --skip-provision \
  --skip-code \
  --skip-refresh \
  --prepare-only