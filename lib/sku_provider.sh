#!/usr/bin/env bash
# ==============================================================================
# Generic SKU Provider Fetching
# ==============================================================================
# This library provides a generalized mechanism to fetch SKUs for any Azure
# resource provider, allowing the script to be extensible for new resource
# types without hardcoding specific provider logic.

# Optional: Set LOG_FILE and CACHE_DIR if not already set
LOG_FILE="${LOG_FILE:-.cache/fetch.log}"
CACHE_DIR="${CACHE_DIR:-.cache}"

# ==============================================================================
# Fetch SKUs for a specific provider from Azure REST API
# 
# This is the core generalized function that works for any provider offering
# an /skus endpoint (Microsoft.Storage, Microsoft.Compute, Microsoft.OpenAI, etc.)
#
# Usage:
#   fetch_provider_skus "Microsoft.Storage" "2021-06-01"
#   fetch_provider_skus "Microsoft.Compute" "2021-03-01"
#   fetch_provider_skus "Microsoft.DBforPostgreSQL" "2021-06-01"
#
# Returns: 0 on success, 1 on failure
# Output: JSON array cached to: $CACHE_DIR/skus_${provider_normalized}.json
# ==============================================================================
fetch_provider_skus() {
    local provider="$1"
    local api_version="${2:-2021-06-01}"  # Default to reasonable API version
    
    if [[ -z "$provider" ]]; then
        log_error "fetch_provider_skus: provider name required" >&2
        return 1
    fi
    
    # Normalize provider name for cache filename (remove dots, lowercase)
    local provider_normalized="${provider//./}"
    provider_normalized="${provider_normalized,,}"
    
    local cache_file="${CACHE_DIR}/skus_${provider_normalized}.json"
    
    log_info "Fetching SKUs for provider: $provider" >&2
    
    if is_cache_valid "$cache_file"; then
        log_info "Using cached SKUs for $provider" >&2
        increment_cache_hit
        echo "$cache_file"
        return 0
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id -o tsv 2>/dev/null)
    if [[ -z "$subscription_id" ]]; then
        log_warning "Could not retrieve subscription ID for $provider SKU fetch" >&2
        echo "[]" > "$cache_file"
        return 1
    fi
    
    log_info "Querying Azure REST API for $provider SKUs (api-version: $api_version)..." >&2
    
    local endpoint="https://management.azure.com/subscriptions/${subscription_id}/providers/${provider}/skus"
    local params="api-version=${api_version}"
    
    # Try REST API call
    if az rest --method get --url "${endpoint}?${params}" --output json > "$cache_file" 2>> "${LOG_FILE}"; then
        # Normalize response - some endpoints return {value: [...]}, others just return [...]
        local temp_file="/tmp/skus_fetch_$$.json"
        
        # Check if response has a 'value' key at top level
        if jq -e '.value' "$cache_file" > /dev/null 2>&1; then
            jq '.value' "$cache_file" > "$temp_file"
            mv "$temp_file" "$cache_file"
        fi
        
        local sku_count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        log_success "Retrieved $sku_count SKUs for $provider" >&2
        increment_api_call
        echo "$cache_file"
        return 0
    else
        log_warning "Could not fetch SKUs for $provider (API endpoint may not support /skus)" >&2
        echo "[]" > "$cache_file"
        return 1
    fi
}

# ==============================================================================
# Fetch SKUs for a specific location/region for a provider
#
# Usage:
#   fetch_provider_region_skus "Microsoft.Compute" "eastus" "2021-03-01"
#
# Returns: 0 on success, 1 on failure
# Output: JSON array cached to: $CACHE_DIR/skus_${provider}_${region}.json
# ==============================================================================
fetch_provider_region_skus() {
    local provider="$1"
    local region="$2"
    local api_version="${3:-2021-06-01}"
    
    if [[ -z "$provider" || -z "$region" ]]; then
        log_error "fetch_provider_region_skus: provider and region required" >&2
        return 1
    fi
    
    # Normalize provider name for cache filename
    local provider_normalized="${provider//./}"
    provider_normalized="${provider_normalized,,}"
    
    local cache_file="${CACHE_DIR}/skus_${provider_normalized}_${region}.json"
    
    log_info "Fetching region-specific SKUs for $provider in $region" >&2
    
    if is_cache_valid "$cache_file"; then
        log_info "Using cached SKUs for $provider in $region" >&2
        increment_cache_hit
        echo "$cache_file"
        return 0
    fi
    
    local subscription_id
    subscription_id=$(az account show --query id -o tsv 2>/dev/null)
    if [[ -z "$subscription_id" ]]; then
        log_warning "Could not retrieve subscription ID for $provider region SKU fetch" >&2
        echo "[]" > "$cache_file"
        return 1
    fi
    
    log_info "Querying Azure REST API for $provider SKUs in $region (api-version: $api_version)..." >&2
    
    local endpoint="https://management.azure.com/subscriptions/${subscription_id}/providers/${provider}/skus"
    local params="api-version=${api_version}"
    
    # Try REST API call
    if az rest --method get --url "${endpoint}?${params}" --output json > "$cache_file" 2>> "${LOG_FILE}"; then
        # Normalize response and filter to region
        local temp_file="/tmp/skus_region_$$.json"
        local region_lower="${region,,}"
        
        # Extract value array if present, then filter for region
        local query='.value // . | map(select(.locations != null and (.locations[] | ascii_downcase == $region_lower)))'
        
        if jq --arg region "$region_lower" "$query" "$cache_file" > "$temp_file" 2>/dev/null; then
            mv "$temp_file" "$cache_file"
        else
            echo "[]" > "$cache_file"
        fi
        
        local sku_count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        log_success "Retrieved $sku_count region-specific SKUs for $provider in $region" >&2
        increment_api_call
        echo "$cache_file"
        return 0
    else
        log_warning "Could not fetch region SKUs for $provider in $region" >&2
        echo "[]" > "$cache_file"
        return 1
    fi
}

# ==============================================================================
# Query provider SKUs to check if a specific SKU is available
#
# Usage:
#   check_provider_sku_available "Microsoft.Storage" "Standard_LRS" "eastus"
#   check_provider_sku_available "Microsoft.Compute" "Standard_B2ms" "swedencentral"
#
# Returns: 0 if SKU available, 1 if not available or not found
# ==============================================================================
check_provider_sku_available() {
    local provider="$1"
    local sku_name="$2"
    local region="$3"
    
    if [[ -z "$provider" || -z "$sku_name" || -z "$region" ]]; then
        return 1
    fi
    
    local cache_file
    cache_file=$(fetch_provider_skus "$provider") || return 1
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    local region_lower="${region,,}"
    local sku_info
    
    # Look for SKU in the cache with case-insensitive location matching
    sku_info=$(jq --arg sku "$sku_name" --arg region "$region_lower" '
        .[] |
        select((.name == $sku or .kind == $sku) and
               (.locations != null and 
                ([.locations[] | ascii_downcase] | index($region)) != null))
    ' "$cache_file" 2>/dev/null | head -n 1)
    
    if [[ -n "$sku_info" ]]; then
        # Check for restrictions
        local restrictions=$(echo "$sku_info" | jq '.restrictions // []')
        local has_restrictions=$(echo "$restrictions" | jq '. | length > 0')
        
        if [[ "$has_restrictions" == "true" ]]; then
            # SKU has restrictions in this region
            return 1
        fi
        
        # SKU is available
        return 0
    fi
    
    # SKU not found
    return 1
}

# ==============================================================================
# Get SKU info (name, locations, restrictions, etc.) for debugging
#
# Usage:
#   get_provider_sku_info "Microsoft.Storage" "Standard_LRS"
#
# Returns: JSON object with SKU details, or empty if not found
# ==============================================================================
get_provider_sku_info() {
    local provider="$1"
    local sku_name="$2"
    
    if [[ -z "$provider" || -z "$sku_name" ]]; then
        return 1
    fi
    
    local cache_file
    cache_file=$(fetch_provider_skus "$provider") || return 1
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    jq --arg sku "$sku_name" '
        .[] |
        select(.name == $sku or .kind == $sku)
    ' "$cache_file" 2>/dev/null
}

# ==============================================================================
# List all unique SKU names for a provider
#
# Usage:
#   list_provider_skus "Microsoft.Storage"
#   list_provider_skus "Microsoft.Compute" | head -20
#
# Returns: Newline-separated list of SKU names
# ==============================================================================
list_provider_skus() {
    local provider="$1"
    
    if [[ -z "$provider" ]]; then
        return 1
    fi
    
    local cache_file
    cache_file=$(fetch_provider_skus "$provider") || return 1
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    jq -r '.[] | .name // .kind // "unknown"' "$cache_file" 2>/dev/null | sort -u
}

# ==============================================================================
# List all locations where a provider has SKUs available
#
# Usage:
#   list_provider_locations "Microsoft.Storage"
#
# Returns: Newline-separated list of region codes
# ==============================================================================
list_provider_locations() {
    local provider="$1"
    
    if [[ -z "$provider" ]]; then
        return 1
    fi
    
    local cache_file
    cache_file=$(fetch_provider_skus "$provider") || return 1
    
    if [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    jq -r '.[] | .locations[]? | ascii_downcase' "$cache_file" 2>/dev/null | sort -u
}

export -f fetch_provider_skus
export -f fetch_provider_region_skus
export -f check_provider_sku_available
export -f get_provider_sku_info
export -f list_provider_skus
export -f list_provider_locations
