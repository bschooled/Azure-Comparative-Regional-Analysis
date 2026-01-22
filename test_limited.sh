#!/bin/bash
source lib/utils_log.sh
source lib/utils_http.sh
source lib/utils_cache.sh
source lib/service_comparison.sh

export LOG_FILE=/tmp/test_limited.log
export CACHE_DIR=.cache
mkdir -p "$CACHE_DIR"

# Test with just 5 providers including Microsoft.Compute
test_providers="Microsoft.Compute
Microsoft.Storage
Microsoft.Network
Dell.Storage
Astronomer.Astro"

echo "Testing with 5 providers..."
echo "$test_providers" | while IFS= read -r provider; do
    if [[ -z "$provider" ]]; then
        continue
    fi
    echo "Testing $provider..."
    result=$(query_provider_skus "westus2" "$provider" 2>&1)
    count=$(echo "$result" | jq '. | length' 2>/dev/null || echo "ERROR")
    echo "  Result: $count SKUs"
done
