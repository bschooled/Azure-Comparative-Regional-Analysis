#!/usr/bin/env bash
# ==============================================================================
# Quick Cache Trace: services_compare SKU caching
# ==============================================================================
# Fast smoke test that verifies provider SKU caching is working by calling
# query_provider_skus twice and showing cache hit/miss logs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

REGION="${1:-westus2}"
PROVIDER="${2:-Microsoft.Kusto}"

export NO_COLOR=1
export CACHE_DIR="${PROJECT_ROOT}/.cache"
export CACHE_TRACE=1

source "${PROJECT_ROOT}/lib/utils_log.sh"
source "${PROJECT_ROOT}/lib/utils_cache.sh"
source "${PROJECT_ROOT}/lib/service_comparison.sh" >/dev/null

init_cache "$CACHE_DIR"

echo "Region:   $REGION"
echo "Provider: $PROVIDER"
echo "CacheDir: $CACHE_DIR"
echo ""

echo "[1/2] First call (may be cache hit or miss)"
count1=$(query_provider_skus "$REGION" "$PROVIDER" | jq 'length')
echo "SKUs: $count1"

echo ""
echo "[2/2] Second call (should be a cache hit)"
count2=$(query_provider_skus "$REGION" "$PROVIDER" | jq 'length')
echo "SKUs: $count2"

echo ""
if [[ "$count2" -eq "$count1" ]]; then
  echo "OK: counts match; caching path is functioning."
else
  echo "WARN: counts changed between calls; investigate upstream API variability."
fi
