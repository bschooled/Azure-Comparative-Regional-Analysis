#!/usr/bin/env bash
# ==============================================================================
# Target Region Availability Checks
# ==============================================================================

# Output files
AVAILABILITY_FILE="${OUTPUT_DIR}/target_region_availability.json"

# Cache files for SKU listings (will be populated at runtime with TARGET_REGION)
# These will be defined in the check_target_availability function
PROVIDERS_CACHE="${CACHE_DIR}/providers.json"

# ==============================================================================
# Get cache file paths (called at runtime when TARGET_REGION is known)
# ==============================================================================
get_sku_cache_paths() {
    COMPUTE_SKUS_CACHE="${CACHE_DIR}/compute_skus_${TARGET_REGION}.json"
    STORAGE_SKUS_CACHE="${CACHE_DIR}/storage_skus_${TARGET_REGION}.json"
}

# ==============================================================================
# Fetch SKUs using the generalized provider mechanism
# 
# This function leverages fetch_provider_skus for ANY resource provider,
# making it easy to extend support to new resource types without writing
# provider-specific logic.
# ==============================================================================
fetch_and_cache_provider_skus() {
    local provider="$1"
    local cache_var="$2"
    local api_version="${3:-2021-06-01}"
    
    log_info "Fetching SKUs for $provider (api-version: $api_version)..."
    
    # Use generalized provider fetching
    local cache_file
    cache_file=$(fetch_provider_skus "$provider" "$api_version") || return 1
    
    # Set the variable in the caller's scope via a global
    eval "$cache_var=$cache_file"
    
    return 0
}

# ==============================================================================
# Check target region availability for all resources
# ==============================================================================
check_target_availability() {
    log_info "Checking resource availability in target region: $TARGET_REGION"
    
    # Set cache file paths now that TARGET_REGION is known
    COMPUTE_SKUS_CACHE="${CACHE_DIR}/compute_skus_${TARGET_REGION}.json"
    STORAGE_SKUS_CACHE="${CACHE_DIR}/storage_skus_${TARGET_REGION}.json"
    
    if [[ ! -f "$TUPLES_FILE" ]]; then
        log_error "Tuples file not found: $TUPLES_FILE"
        return 1
    fi

    # Fast-path: if source and target region are the same, everything found in
    # the inventory is considered available in the target by definition.
    if [[ "$TARGET_REGION" == "$SOURCE_REGION" ]]; then
        local availability_results="[]"
        while IFS= read -r tuple; do
            local resource_type=$(echo "$tuple" | jq -r '.type')
            local arm_sku=$(echo "$tuple" | jq -r '.armSkuName // .sku // .vmSize // ""')
            availability_results=$(echo "$availability_results" | jq -c \
                --arg type "$resource_type" \
                --arg region "$TARGET_REGION" \
                --arg arm "$arm_sku" '
                    . + [{
                        type: $type,
                        armSkuName: (if $arm == "" then null else $arm end),
                        targetRegion: $region,
                        available: true,
                        evidence: "Source and target region are the same"
                    }]
                ')
        done < <(jq -c '.[]' "$TUPLES_FILE")

        # Write results, checking validity first to handle pipefail
        if echo "$availability_results" | jq empty 2>/dev/null; then
            echo "$availability_results" > "$AVAILABILITY_FILE"
        else
            echo "[]" > "$AVAILABILITY_FILE"
        fi
        local total_count=$(jq '. | length' "$AVAILABILITY_FILE")
        log_success "Availability check complete: ${total_count}/${total_count} available, 0 unavailable"
        return 0
    fi
    
    # Fetch/cache SKU and provider data using generalized provider mechanism
    fetch_compute_skus
    fetch_storage_skus
    fetch_providers_info
    
    # Process each tuple
    local availability_results="[]"
    
    while IFS= read -r tuple; do
        local result=$(check_tuple_availability "$tuple")
        # Accumulate results, suppressing only jq errors
        availability_results=$(echo "$availability_results" | jq -c ". + [$result]" 2>/dev/null) || {
            log_debug "Failed to accumulate result for tuple, skipping" >&2
            continue
        }
    done < <(jq -c '.[]' "$TUPLES_FILE")
    
    # Validate JSON before writing
    if echo "$availability_results" | jq empty 2>/dev/null; then
        # Write already-validated JSON, no need to pipe through jq again
        echo "$availability_results" > "$AVAILABILITY_FILE"
    else
        log_warning "Invalid JSON accumulated during availability check; writing empty array"
        echo "[]" > "$AVAILABILITY_FILE"
    fi
    
    local available_count=$(jq '[.[] | select(.available == true)] | length' "$AVAILABILITY_FILE")
    local total_count=$(jq '. | length' "$AVAILABILITY_FILE")
    local unavailable_count=$((total_count - available_count))
    
    log_success "Availability check complete: $available_count/$total_count available, $unavailable_count unavailable"
    
    if [[ $unavailable_count -gt 0 ]]; then
        log_warning "Some resources are not available in target region. See: $AVAILABILITY_FILE"
    fi
}

# ==============================================================================
# Fetch compute SKUs for target region
# ==============================================================================
fetch_compute_skus() {
    log_info "Fetching compute SKUs for target region..."
    
    # Use the generalized provider fetching mechanism
    # This automatically handles caching and API calls
    local provider="Microsoft.Compute"
    local api_version="2021-03-01"
    
    # Fetch from provider and cache locally with region suffix
    if fetch_provider_skus "$provider" "$api_version" > /dev/null 2>&1; then
        # Copy to region-specific cache for backward compatibility
        local source_cache="${CACHE_DIR}/skus_microsoftcompute.json"
        if [[ -f "$source_cache" ]]; then
            cp "$source_cache" "$COMPUTE_SKUS_CACHE" 2>/dev/null || return 1
            local sku_count=$(jq '. | length' "$COMPUTE_SKUS_CACHE" 2>/dev/null || echo 0)
            log_success "Retrieved $sku_count compute SKUs"
            return 0
        fi
    fi
    
    log_error "Failed to fetch compute SKUs"
    return 1
}

# ==============================================================================
# Fetch storage SKUs
# ==============================================================================
fetch_storage_skus() {
    log_info "Fetching storage SKUs..."
    
    # Use the generalized provider fetching mechanism
    local provider="Microsoft.Storage"
    local api_version="2021-06-01"
    
    # Fetch from provider and cache locally with region suffix
    if fetch_provider_skus "$provider" "$api_version" > /dev/null 2>&1; then
        # Copy to region-specific cache for backward compatibility
        local source_cache="${CACHE_DIR}/skus_microsoftstorage.json"
        if [[ -f "$source_cache" ]]; then
            cp "$source_cache" "$STORAGE_SKUS_CACHE" 2>/dev/null || return 1
            local sku_count=$(jq '. | length' "$STORAGE_SKUS_CACHE" 2>/dev/null || echo 0)
            log_success "Retrieved $sku_count storage SKUs"
            return 0
        fi
    fi
    
    log_warning "Could not fetch storage account SKUs; storage availability will use service-level check"
    echo "[]" > "$STORAGE_SKUS_CACHE"
    return 0
}

# ==============================================================================
# Fetch provider information
# ==============================================================================
fetch_providers_info() {
    log_info "Fetching provider information..."
    
    if is_cache_valid "$PROVIDERS_CACHE"; then
        log_info "Using cached provider information"
        increment_cache_hit
        return 0
    fi
    
    log_info "Querying Azure for provider information..."
    
    if az provider list --expand "resourceTypes/locations" --output json > "$PROVIDERS_CACHE" 2>> "${LOG_FILE}"; then
        local provider_count=$(jq '. | length' "$PROVIDERS_CACHE")
        log_success "Retrieved information for $provider_count providers"
        increment_api_call
    else
        log_error "Failed to fetch provider information"
        return 1
    fi
}

# ==============================================================================
# Helper: Convert region code to display name for provider location matching
# ==============================================================================
normalize_region_name() {
    local region_code="${1,,}"
    
    # Build mapping from region code to display name
    # This is auto-generated from az account list-locations
    case "$region_code" in
        # US Regions
        eastus) echo "East US" ;;
        eastus2) echo "East US 2" ;;
        eastus3) echo "East US 3" ;;
        westus) echo "West US" ;;
        westus2) echo "West US 2" ;;
        westus3) echo "West US 3" ;;
        westus4) echo "West US 4" ;;
        centralus) echo "Central US" ;;
        northcentralus) echo "North Central US" ;;
        southcentralus) echo "South Central US" ;;
        westcentralus) echo "West Central US" ;;
        
        # Europe Regions
        northeurope) echo "North Europe" ;;
        westeurope) echo "West Europe" ;;
        francecentral) echo "France Central" ;;
        francesouth) echo "France South" ;;
        germanynorth) echo "Germany North" ;;
        germanywestcentral) echo "Germany West Central" ;;
        polandcentral) echo "Poland Central" ;;
        norwayeast) echo "Norway East" ;;
        norwaywest) echo "Norway West" ;;
        switzerlandnorth) echo "Switzerland North" ;;
        switzerlandwest) echo "Switzerland West" ;;
        uksouth) echo "UK South" ;;
        ukwest) echo "UK West" ;;
        swedencentral) echo "Sweden Central" ;;
        belgiumcentral) echo "Belgium Central" ;;
        austriaeast) echo "Austria East" ;;
        spaincentral) echo "Spain Central" ;;
        italynorth) echo "Italy North" ;;
        
        # Asia Pacific Regions
        southeastasia) echo "Southeast Asia" ;;
        eastasia) echo "East Asia" ;;
        japaneast) echo "Japan East" ;;
        japanwest) echo "Japan West" ;;
        australiaeast) echo "Australia East" ;;
        australiasoutheast) echo "Australia Southeast" ;;
        australiacentral) echo "Australia Central" ;;
        australiacentral2) echo "Australia Central 2" ;;
        koreacentral) echo "Korea Central" ;;
        koreasouth) echo "Korea South" ;;
        newzealandnorth) echo "New Zealand North" ;;
        indonesiacentral) echo "Indonesia Central" ;;
        malaysiawest) echo "Malaysia West" ;;
        
        # India Regions
        westindia) echo "West India" ;;
        southindia) echo "South India" ;;
        centralindia) echo "Central India" ;;
        jioindiacentral) echo "Jio India Central" ;;
        jioindiawest) echo "Jio India West" ;;
        
        # Middle East & Africa
        uaenorth) echo "UAE North" ;;
        uaecentral) echo "UAE Central" ;;
        southafricanorth) echo "South Africa North" ;;
        southafricawest) echo "South Africa West" ;;
        qatarcentral) echo "Qatar Central" ;;
        israelcentral) echo "Israel Central" ;;
        
        # Americas Regions
        canadacentral) echo "Canada Central" ;;
        canadaeast) echo "Canada East" ;;
        brazilsouth) echo "Brazil South" ;;
        brazilsoutheast) echo "Brazil Southeast" ;;
        mexicocentral) echo "Mexico Central" ;;
        chilecentral) echo "Chile Central" ;;
        
        # Stage/Special Regions (fallback)
        centraluseuap) echo "Central US EUAP" ;;
        eastus2euap) echo "East US 2 EUAP" ;;
        centralusstage) echo "Central US (Stage)" ;;
        eastus2stage) echo "East US 2 (Stage)" ;;
        eastusstage) echo "East US (Stage)" ;;
        northcentralusstage) echo "North Central US (Stage)" ;;
        southcentralusstage) echo "South Central US (Stage)" ;;
        westusstage) echo "West US (Stage)" ;;
        westus2stage) echo "West US 2 (Stage)" ;;
        eastasiastage) echo "East Asia (Stage)" ;;
        southeastasiastage) echo "Southeast Asia (Stage)" ;;
        
        # Fallback for region codes we might not have covered
        *) echo "$1" ;;
    esac
}

# ==============================================================================
# Helper: Check if a service type is available in the target region
# ==============================================================================
check_service_type_in_region() {
    local resource_type="$1"
    
    # Parse provider namespace and resource type
    local provider_namespace="${resource_type%%/*}"
    local resource_type_name="${resource_type#*/}"
    
    # Convert region code to display name for matching against provider locations
    local region_display_name=$(normalize_region_name "$TARGET_REGION")
    
    # Query provider cache for this service type in target region
    local provider_info=$(jq --arg ns "$provider_namespace" --arg rt "$resource_type_name" --arg region "$region_display_name" '
        .[] |
        select((.namespace | ascii_downcase) == ($ns | ascii_downcase)) |
        .resourceTypes[] |
        select((.resourceType | ascii_downcase) == ($rt | ascii_downcase) and 
               ([.locations[]] | map(select(. == $region)) | length > 0))
    ' "$PROVIDERS_CACHE" 2>/dev/null | head -n 1)
    
    if [[ -n "$provider_info" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# ==============================================================================
# Check availability for a single tuple
# ==============================================================================
check_tuple_availability() {
    local tuple="$1"
    local resource_type=$(echo "$tuple" | jq -r '.type | ascii_downcase')
    
    case "$resource_type" in
        microsoft.compute/virtualmachines)
            check_vm_availability "$tuple"
            ;;
        microsoft.compute/disks)
            check_disk_availability "$tuple"
            ;;
        microsoft.storage/storageaccounts)
            check_storage_availability "$tuple"
            ;;
        *)
            check_generic_availability "$tuple"
            ;;
    esac
}

# ==============================================================================
# Check VM availability
# ==============================================================================
check_vm_availability() {
    local tuple="$1"
    local vm_size=$(echo "$tuple" | jq -r '.vmSize')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    # First check if the service type (Microsoft.Compute/virtualMachines) is available in target region
    local service_available=$(check_service_type_in_region "$resource_type")
    
    if [[ "$service_available" != "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"armSkuName\": null, \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": false, \"skuAvailable\": null, \"available\": false, \"reason\": \"Service type not available in target region\"}"
        return
    fi
    
    if [[ -z "$vm_size" || "$vm_size" == "null" ]]; then
        echo "{\"type\": \"$resource_type\", \"armSkuName\": null, \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"reason\": \"No VM size specified\"}"
        return
    fi
    
    # Check if the specific SKU is available in compute SKUs cache
    local sku_info=$(jq --arg vmsize "$vm_size" --arg region "$TARGET_REGION" '
        .[] | 
        select(.resourceType == "virtualMachines" and .name == $vmsize and 
               (.locations[] | ascii_downcase) == ($region | ascii_downcase))
    ' "$COMPUTE_SKUS_CACHE" 2>/dev/null | head -n 1)
    
    if [[ -z "$sku_info" ]]; then
        echo "{\"type\": \"$resource_type\", \"armSkuName\": \"$vm_size\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"reason\": \"VM size not found in target region\"}"
        return
    fi
    
    # Check for restrictions
    local restrictions=$(echo "$sku_info" | jq -c '.restrictions // []')
    local has_restrictions=$(echo "$restrictions" | jq '. | length > 0')
    
    if [[ "$has_restrictions" == "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"armSkuName\": \"$vm_size\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"restrictions\": $restrictions, \"reason\": \"SKU has restrictions\"}"
    else
        echo "{\"type\": \"$resource_type\", \"armSkuName\": \"$vm_size\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": true, \"available\": true, \"restrictions\": []}"
    fi
}

# ==============================================================================
# Check disk availability
# ==============================================================================
check_disk_availability() {
    local tuple="$1"
    local disk_sku=$(echo "$tuple" | jq -r '.diskSku')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    # First check if the service type is available in target region
    local service_available=$(check_service_type_in_region "$resource_type")
    
    if [[ "$service_available" != "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": null, \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": false, \"skuAvailable\": null, \"available\": false, \"reason\": \"Service type not available in target region\"}"
        return
    fi
    
    if [[ -z "$disk_sku" || "$disk_sku" == "null" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": null, \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"reason\": \"No disk SKU specified\"}"
        return
    fi
    
    # Check in compute SKUs cache for disk types
    local sku_info=$(jq --arg disksku "$disk_sku" --arg region "$TARGET_REGION" '
        .[] | 
        select(.resourceType == "disks" and .name == $disksku and 
               (.locations[] | ascii_downcase) == ($region | ascii_downcase))
    ' "$COMPUTE_SKUS_CACHE" 2>/dev/null | head -n 1)
    
    if [[ -z "$sku_info" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": \"$disk_sku\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"reason\": \"Disk SKU not found in target region\"}"
        return
    fi
    
    local restrictions=$(echo "$sku_info" | jq -c '.restrictions // []')
    local has_restrictions=$(echo "$restrictions" | jq '. | length > 0')
    
    if [[ "$has_restrictions" == "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": \"$disk_sku\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"restrictions\": $restrictions, \"reason\": \"SKU has restrictions\"}"
    else
        echo "{\"type\": \"$resource_type\", \"sku\": \"$disk_sku\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": true, \"available\": true, \"restrictions\": []}"
    fi
}

# ==============================================================================
# Check storage account availability
# ==============================================================================
check_storage_availability() {
    local tuple="$1"
    local sku=$(echo "$tuple" | jq -r '.sku')
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    # First check if the service type is available in target region
    local service_available=$(check_service_type_in_region "$resource_type")
    
    if [[ "$service_available" != "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": null, \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": false, \"skuAvailable\": null, \"available\": false, \"reason\": \"Service type not available in target region\"}"
        return
    fi
    
    if [[ -z "$sku" || "$sku" == "null" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": null, \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"reason\": \"No storage SKU specified\"}"
        return
    fi
    
    # Check in storage SKUs cache
    local sku_info=$(jq --arg sku "$sku" --arg region "$TARGET_REGION" '
        .[] |
        select(.name == $sku and 
               ([.locations[] | ascii_downcase] | index($region | ascii_downcase)) != null)
    ' "$STORAGE_SKUS_CACHE" 2>/dev/null | head -n 1)
    
    if [[ -z "$sku_info" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": \"$sku\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"reason\": \"Storage SKU not available in target region\"}"
        return
    fi
    
    local restrictions=$(echo "$sku_info" | jq -c '.restrictions // []')
    local has_restrictions=$(echo "$restrictions" | jq '. | length > 0')
    
    if [[ "$has_restrictions" == "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"sku\": \"$sku\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": false, \"available\": false, \"restrictions\": $restrictions, \"reason\": \"SKU has restrictions\"}"
    else
        echo "{\"type\": \"$resource_type\", \"sku\": \"$sku\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"skuAvailable\": true, \"available\": true, \"restrictions\": []}"
    fi
}

# ==============================================================================
# Check generic resource availability via provider lookup
# ==============================================================================
check_generic_availability() {
    local tuple="$1"
    local resource_type=$(echo "$tuple" | jq -r '.type')
    
    # Check if service type is available in target region
    local service_available=$(check_service_type_in_region "$resource_type")
    
    if [[ "$service_available" != "true" ]]; then
        echo "{\"type\": \"$resource_type\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": false, \"available\": false, \"reason\": \"Resource type not found in provider location list for target region\"}"
        return
    fi
    
    echo "{\"type\": \"$resource_type\", \"targetRegion\": \"$TARGET_REGION\", \"serviceAvailable\": true, \"available\": true, \"reason\": \"Provider lookup shows $TARGET_REGION in supported locations\"}"
}
