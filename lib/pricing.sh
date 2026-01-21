#!/usr/bin/env bash
# ==============================================================================
# Pricing Meter Enrichment via Azure Retail Prices API
# ==============================================================================

# Azure Retail Prices API endpoint
RETAIL_PRICES_API="https://prices.azure.com/api/retail/prices"

# Output files
PRICE_LOOKUP_FILE="${OUTPUT_DIR}/price_lookup.csv"
UNPRICED_FILE="${OUTPUT_DIR}/unpriced_resources.json"

# ==============================================================================
# Fetch pricing data for all unique tuples
# ==============================================================================
fetch_pricing_data() {
    log_info "Fetching pricing data from Azure Retail Prices API..."
    
    if [[ ! -f "$TUPLES_FILE" ]]; then
        log_error "Tuples file not found: $TUPLES_FILE"
        return 1
    fi
    
    local tuple_count=$(jq '. | length' "$TUPLES_FILE")
    log_info "Processing $tuple_count unique resource tuples"
    
    # Initialize output files
    echo "type,armSkuName,armRegionName,serviceName,serviceFamily,meterName,productName,skuName,unitOfMeasure,retailPrice,currencyCode" > "$PRICE_LOOKUP_FILE"
    echo "[]" > "$UNPRICED_FILE"
    
    # Create temporary directory for parallel processing
    local temp_dir="${OUTPUT_DIR}/.pricing_temp"
    mkdir -p "$temp_dir"
    
    # Export tuples to individual files for parallel processing
    jq -c '.[]' "$TUPLES_FILE" | while IFS= read -r tuple; do
        local tuple_hash=$(echo "$tuple" | cache_key)
        echo "$tuple" > "${temp_dir}/${tuple_hash}.json"
    done
    
    # Process tuples in parallel
    export -f fetch_pricing_for_tuple
    export -f http_get_with_retry
    export -f increment_api_call
    export -f get_cache
    export -f set_cache
    export -f cache_key
    export -f is_cache_valid
    export -f log_info
    export -f log_error
    export -f log_debug
    export -f log_warning
    export -f increment_cache_hit
    export -f build_pricing_filter
    export -f url_encode
    export RETAIL_PRICES_API
    export CACHE_DIR
    export LOG_FILE
    export SOURCE_REGION
    
    find "$temp_dir" -name "*.json" -type f | \
        xargs -P "$PARALLEL" -I {} bash -c 'fetch_pricing_for_tuple "{}"' 2>> "${LOG_FILE}"
    
    # Aggregate results
    log_info "Aggregating pricing results..."
    
    find "$temp_dir" -name "*.csv" -type f | while read -r result_file; do
        cat "$result_file" >> "$PRICE_LOOKUP_FILE"
    done
    
    # Collect unpriced resources
    local unpriced_array="[]"
    find "$temp_dir" -name "*.unpriced.json" -type f | while read -r unpriced_file; do
        local content=$(cat "$unpriced_file")
        unpriced_array=$(echo "$unpriced_array" | jq -c ". + [$content]")
    done
    echo "$unpriced_array" > "$UNPRICED_FILE"
    
    # Clean up
    rm -rf "$temp_dir"
    
    local priced_count=$(tail -n +2 "$PRICE_LOOKUP_FILE" | wc -l)
    local unpriced_count=$(jq '. | length' "$UNPRICED_FILE")
    
    log_success "Pricing lookup complete: $priced_count priced, $unpriced_count unpriced"
    
    if [[ $unpriced_count -gt 0 ]]; then
        log_warning "Some resources could not be priced. See: $UNPRICED_FILE"
    fi
}

# ==============================================================================
# Fetch pricing for a single tuple
# ==============================================================================
fetch_pricing_for_tuple() {
    local tuple_file="$1"
    local tuple=$(cat "$tuple_file")
    local tuple_hash=$(basename "$tuple_file" .json)
    local output_dir=$(dirname "$tuple_file")
    
    local resource_type=$(echo "$tuple" | jq -r '.type')
    local region=$(echo "$tuple" | jq -r '.region')
    
    # Check if resource type has direct meter
    if ! has_direct_meter "$resource_type"; then
        echo "$tuple" > "${output_dir}/${tuple_hash}.unpriced.json"
        return 0
    fi
    
    # Check cache
    local cache_key_str="pricing_${resource_type}_${region}_${tuple_hash}"
    local cached_result=$(get_cache "$cache_key_str")
    
    if [[ $? -eq 0 ]]; then
        echo "$cached_result" > "${output_dir}/${tuple_hash}.csv"
        return 0
    fi
    
    # Determine pricing lookup strategy based on resource type
    local pricing_result=""
    
    case "$resource_type" in
        Microsoft.Compute/virtualMachines)
            pricing_result=$(lookup_vm_pricing "$tuple")
            ;;
        Microsoft.Compute/disks)
            pricing_result=$(lookup_disk_pricing "$tuple")
            ;;
        Microsoft.Storage/storageAccounts)
            pricing_result=$(lookup_storage_pricing "$tuple")
            ;;
        Microsoft.Network/*)
            pricing_result=$(lookup_network_pricing "$tuple")
            ;;
        *)
            pricing_result=$(lookup_generic_pricing "$tuple")
            ;;
    esac
    
    if [[ -n "$pricing_result" ]]; then
        echo "$pricing_result" > "${output_dir}/${tuple_hash}.csv"
        set_cache "$cache_key_str" "$pricing_result"
    else
        echo "$tuple" > "${output_dir}/${tuple_hash}.unpriced.json"
    fi
}

# ==============================================================================
# Lookup VM pricing
# ==============================================================================
lookup_vm_pricing() {
    local tuple="$1"
    local vm_size=$(echo "$tuple" | jq -r '.vmSize')
    local region=$(echo "$tuple" | jq -r '.region')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    if [[ -z "$vm_size" || "$vm_size" == "null" ]]; then
        return 1
    fi
    
    local filter=$(build_pricing_filter "Virtual Machines" "$region" "$vm_size")
    local encoded_filter=$(url_encode "$filter")
    local url="${RETAIL_PRICES_API}?\$filter=${encoded_filter}"
    
    local response=$(http_get_with_retry "$url")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    # Extract first matching item (prefer Linux pricing)
    echo "$response" | jq -r '.Items[] | 
        select(.armSkuName == "'$vm_size'") |
        "'"$resource_type"'," + (.armSkuName // "") + "," + (.armRegionName // "") + "," +
        (.serviceName // "") + "," + (.serviceFamily // "") + "," + (.meterName // "") + "," +
        (.productName // "") + "," + (.skuName // "") + "," + (.unitOfMeasure // "") + "," +
        (.retailPrice | tostring) + "," + (.currencyCode // "")
    ' | head -n 1
}

# ==============================================================================
# Lookup disk pricing
# ==============================================================================
lookup_disk_pricing() {
    local tuple="$1"
    local disk_sku=$(echo "$tuple" | jq -r '.diskSku')
    local region=$(echo "$tuple" | jq -r '.region')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    if [[ -z "$disk_sku" || "$disk_sku" == "null" ]]; then
        return 1
    fi
    
    local filter="serviceFamily eq 'Storage' and armRegionName eq '$region' and (armSkuName eq '$disk_sku' or skuName eq '$disk_sku')"
    local encoded_filter=$(url_encode "$filter")
    local url="${RETAIL_PRICES_API}?\$filter=${encoded_filter}"
    
    local response=$(http_get_with_retry "$url")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$response" | jq -r '.Items[] |
        "'"$resource_type"'," + (.armSkuName // "") + "," + (.armRegionName // "") + "," +
        (.serviceName // "") + "," + (.serviceFamily // "") + "," + (.meterName // "") + "," +
        (.productName // "") + "," + (.skuName // "") + "," + (.unitOfMeasure // "") + "," +
        (.retailPrice | tostring) + "," + (.currencyCode // "")
    ' | head -n 1
}

# ==============================================================================
# Lookup storage account pricing
# ==============================================================================
lookup_storage_pricing() {
    local tuple="$1"
    local sku=$(echo "$tuple" | jq -r '.sku')
    local region=$(echo "$tuple" | jq -r '.region')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    if [[ -z "$sku" || "$sku" == "null" ]]; then
        return 1
    fi
    
    local filter="serviceFamily eq 'Storage' and armRegionName eq '$region' and armSkuName eq '$sku'"
    local encoded_filter=$(url_encode "$filter")
    local url="${RETAIL_PRICES_API}?\$filter=${encoded_filter}"
    
    local response=$(http_get_with_retry "$url")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$response" | jq -r '.Items[] |
        "'"$resource_type"'," + (.armSkuName // "") + "," + (.armRegionName // "") + "," +
        (.serviceName // "") + "," + (.serviceFamily // "") + "," + (.meterName // "") + "," +
        (.productName // "") + "," + (.skuName // "") + "," + (.unitOfMeasure // "") + "," +
        (.retailPrice | tostring) + "," + (.currencyCode // "")
    ' | head -n 1
}

# ==============================================================================
# Lookup network resource pricing
# ==============================================================================
lookup_network_pricing() {
    local tuple="$1"
    local sku=$(echo "$tuple" | jq -r '.sku')
    local region=$(echo "$tuple" | jq -r '.region')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    local filter="serviceFamily eq 'Networking' and armRegionName eq '$region'"
    
    if [[ -n "$sku" && "$sku" != "null" ]]; then
        filter="$filter and (armSkuName eq '$sku' or skuName eq '$sku')"
    fi
    
    local encoded_filter=$(url_encode "$filter")
    local url="${RETAIL_PRICES_API}?\$filter=${encoded_filter}"
    
    local response=$(http_get_with_retry "$url")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$response" | jq -r '.Items[] |
        "'"$resource_type"'," + (.armSkuName // "") + "," + (.armRegionName // "") + "," +
        (.serviceName // "") + "," + (.serviceFamily // "") + "," + (.meterName // "") + "," +
        (.productName // "") + "," + (.skuName // "") + "," + (.unitOfMeasure // "") + "," +
        (.retailPrice | tostring) + "," + (.currencyCode // "")
    ' | head -n 1
}

# ==============================================================================
# Lookup generic pricing
# ==============================================================================
lookup_generic_pricing() {
    local tuple="$1"
    local sku=$(echo "$tuple" | jq -r '.sku')
    local region=$(echo "$tuple" | jq -r '.region')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    # Try generic lookup by region
    local filter="armRegionName eq '$region'"
    
    if [[ -n "$sku" && "$sku" != "null" ]]; then
        filter="$filter and armSkuName eq '$sku'"
    fi
    
    local encoded_filter=$(url_encode "$filter")
    local url="${RETAIL_PRICES_API}?\$filter=${encoded_filter}&\$top=10"
    
    local response=$(http_get_with_retry "$url")
    
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    echo "$response" | jq -r '.Items[] |
        "'"$resource_type"'," + (.armSkuName // "") + "," + (.armRegionName // "") + "," +
        (.serviceName // "") + "," + (.serviceFamily // "") + "," + (.meterName // "") + "," +
        (.productName // "") + "," + (.skuName // "") + "," + (.unitOfMeasure // "") + "," +
        (.retailPrice | tostring) + "," + (.currencyCode // "")
    ' | head -n 1
}
