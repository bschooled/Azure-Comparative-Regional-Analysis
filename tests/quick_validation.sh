#!/usr/bin/env bash
# ==============================================================================
# Quick Validation: Generalized SKU Provider Fetching
# ==============================================================================
# Quick smoke test to verify the generalized function works across providers

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export NO_COLOR=1
source "${PROJECT_ROOT}/lib/utils_log.sh"
source "${PROJECT_ROOT}/lib/utils_cache.sh"
source "${PROJECT_ROOT}/lib/sku_provider.sh"

CACHE_DIR="${PROJECT_ROOT}/.cache"
mkdir -p "$CACHE_DIR"

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Quick Validation: Generalized SKU Provider Fetching           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Test 1: Fetch Compute SKUs
echo "[1/8] Fetching Microsoft.Compute SKUs..."
if cache_file=$(fetch_provider_skus "Microsoft.Compute" "2021-03-01"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    if [[ $count -gt 0 ]]; then
        echo "✓ SUCCESS: Retrieved $count compute SKUs"
    else
        echo "✓ OK: Query completed (empty or cached)"
    fi
else
    echo "✗ FAILED: Could not fetch compute SKUs"
fi

# Test 2: Fetch Storage SKUs
echo ""
echo "[2/8] Fetching Microsoft.Storage SKUs..."
if cache_file=$(fetch_provider_skus "Microsoft.Storage" "2021-06-01"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    if [[ $count -gt 0 ]]; then
        echo "✓ SUCCESS: Retrieved $count storage SKUs"
    else
        echo "✓ OK: Query completed (empty or cached)"
    fi
else
    echo "✗ FAILED: Could not fetch storage SKUs"
fi

# Test 3: Fetch PostgreSQL SKUs
echo ""
echo "[3/8] Fetching Microsoft.DBforPostgreSQL SKUs..."
if cache_file=$(fetch_provider_skus "Microsoft.DBforPostgreSQL" "2021-06-01"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    echo "✓ SUCCESS: Query completed ($count SKUs found)"
else
    echo "✗ FAILED: Could not fetch PostgreSQL SKUs"
fi

# Test 4: Fetch MySQL SKUs
echo ""
echo "[4/8] Fetching Microsoft.DBforMySQL SKUs..."
if cache_file=$(fetch_provider_skus "Microsoft.DBforMySQL" "2021-06-01"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    echo "✓ SUCCESS: Query completed ($count SKUs found)"
else
    echo "✗ FAILED: Could not fetch MySQL SKUs"
fi

# Test 5: Fetch Cosmos SKUs
echo ""
echo "[5/8] Fetching Microsoft.DocumentDB SKUs (Cosmos)..."
if cache_file=$(fetch_provider_skus "Microsoft.DocumentDB" "2021-11-15"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    echo "✓ SUCCESS: Query completed ($count SKUs found)"
else
    echo "✗ FAILED: Could not fetch Cosmos SKUs"
fi

# Test 6: Fetch Cache/Redis SKUs
echo ""
echo "[6/8] Fetching Microsoft.Cache SKUs (Redis)..."
if cache_file=$(fetch_provider_skus "Microsoft.Cache" "2021-06-01"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    echo "✓ SUCCESS: Query completed ($count SKUs found)"
else
    echo "✗ FAILED: Could not fetch Redis SKUs"
fi

# Test 7: Fetch Web/AppService SKUs
echo ""
echo "[7/8] Fetching Microsoft.Web SKUs (App Service)..."
if cache_file=$(fetch_provider_skus "Microsoft.Web" "2021-02-01"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    echo "✓ SUCCESS: Query completed ($count SKUs found)"
else
    echo "✗ FAILED: Could not fetch Web SKUs"
fi

# Test 8: Fetch SQL SKUs
echo ""
echo "[8/8] Fetching Microsoft.Sql SKUs..."
if cache_file=$(fetch_provider_skus "Microsoft.Sql" "2021-05-01-preview"); then
    count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
    echo "✓ SUCCESS: Query completed ($count SKUs found)"
else
    echo "✗ FAILED: Could not fetch SQL SKUs"
fi

# Summary
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Cache Files Created                                           ║"
echo "╠════════════════════════════════════════════════════════════════╣"
ls -lh "$CACHE_DIR"/skus_*.json 2>/dev/null | awk '{print "║  " $9 " (" $5 ")"}' || echo "║  (No cache files found)"
echo "╚════════════════════════════════════════════════════════════════╝"

echo ""
echo "✓ Validation complete!"
