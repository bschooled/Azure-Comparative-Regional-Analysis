#!/usr/bin/env bash
# ==============================================================================
# Service Quota Management
# ==============================================================================
# Purpose: Fetch service quotas for resources found in inventory
#          Intelligently deduplicate multi-level quotas (subscription vs family)
#          Fetch target region quota when filtering by subscription/resource group
# 
# Features:
#  - Graceful fallback when quota APIs unavailable
#  - Hierarchical quota handling (service-level, per-type, per-family)
#  - Deduplication to avoid redundant API calls
#  - Source and target region quota tracking
#  - Subscription and resource group aware

# Quota output files
QUOTA_SOURCE_FILE="${OUTPUT_DIR}/quota_source_region.json"
QUOTA_TARGET_FILE="${OUTPUT_DIR}/quota_target_region.json"
QUOTA_SUMMARY_FILE="${OUTPUT_DIR}/quota_summary.csv"

# ==============================================================================
# Service-to-Quota API Mapping
# ==============================================================================
# Maps Azure resource types to their quota endpoints and metrics

# Get quota endpoints for a service
get_quota_endpoints() {
    local resource_type="$1"
    local region="${2:---}"  # Optional region parameter
    
    case "$resource_type" in
        # Compute Quotas
        microsoft.compute/virtualmachines)
            echo "compute.vcpu|compute.vcpu_family"
            ;;
        microsoft.compute/disks)
            echo "compute.disk"
            ;;
        
        # Network Quotas
        microsoft.network/loadbalancers)
            echo "network.load_balancer"
            ;;
        microsoft.network/publicipaddresses)
            echo "network.public_ip"
            ;;
        microsoft.network/natgateways)
            echo "network.nat_gateway"
            ;;
        microsoft.network/applicationgateways)
            echo "network.app_gateway"
            ;;
        
        # Database Quotas
        microsoft.sql/servers/databases)
            echo "sql.database|sql.dtu"
            ;;
        microsoft.dbforpostgresql/flexibleservers)
            echo "postgre.server|postgre.vcpu"
            ;;
        microsoft.dbformysql/flexibleservers)
            echo "mysql.server|mysql.vcpu"
            ;;
        microsoft.documentdb/databaseaccounts)
            echo "cosmos.account|cosmos.throughput"
            ;;
        
        # Cache Quotas
        microsoft.cache/redis)
            echo "redis.cache"
            ;;
        
        # Container Quotas
        microsoft.containerservice/managedclusters)
            echo "container.aks|container.vcpu"
            ;;
        microsoft.containerregistry/registries)
            echo "container.registry"
            ;;
        
        # App Service Quotas
        microsoft.web/serverfarms)
            echo "appservice.plan|appservice.instance"
            ;;
        
        # Storage Quotas
        microsoft.storage/storageaccounts)
            echo "storage.account|storage.capacity"
            ;;
        
        # Key Vault
        microsoft.keyvault/vaults)
            echo "keyvault.vault"
            ;;
        
        # Default: no known quotas
        *)
            return 1
            ;;
    esac
}

# ==============================================================================
# Fetch quota usage for a subscription
# ==============================================================================
fetch_subscription_quota() {
    local subscription_id="$1"
    local region="${2:---}"
    
    log_info "Fetching quota for subscription: $subscription_id (region: $region)" >&2
    
    local endpoint="https://management.azure.com/subscriptions/${subscription_id}/providers/Microsoft.Compute/locations/${region}/usages"
    local api_version="2021-07-01"
    
    if az rest --method get \
        --url "${endpoint}?api-version=${api_version}" \
        --output json 2>/dev/null; then
        return 0
    else
        log_debug "Could not fetch quota from Compute provider; will try service-specific endpoints" >&2
        return 1
    fi
}

# ==============================================================================
# Fetch quota usage via Usage API
# ==============================================================================
fetch_usage_metrics() {
    local subscription_id="$1"
    local resource_type="$2"
    local region="${3:---}"
    
    log_debug "Fetching usage metrics for $resource_type in region $region" >&2
    
    local metric_name
    case "$resource_type" in
        microsoft.compute/virtualmachines)
            metric_name="Virtual Machines"
            ;;
        microsoft.network/loadbalancers)
            metric_name="Load Balancers"
            ;;
        microsoft.sql/servers/databases)
            metric_name="SQL Databases"
            ;;
        microsoft.storage/storageaccounts)
            metric_name="Storage Accounts"
            ;;
        *)
            return 1
            ;;
    esac
    
    # Try to fetch from Compute provider (most comprehensive)
    local endpoint="https://management.azure.com/subscriptions/${subscription_id}/providers/Microsoft.Compute/locations/${region}/usages"
    local api_version="2021-07-01"
    
    az rest --method get \
        --url "${endpoint}?api-version=${api_version}" \
        --output json 2>/dev/null || return 1
}

# ==============================================================================
# Build unique quota list from inventory (avoid duplicates)
# ==============================================================================
build_unique_quota_list() {
    log_info "Building unique quota list from inventory resources" >&2
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE" >&2
        return 1
    fi
    
    # Extract unique services and their quota endpoints
    local quota_specs="[]"
    
    # Process each resource type in inventory
    while IFS= read -r resource_type; do
        # Skip empty lines
        [[ -z "$resource_type" ]] && continue
        
        # Get quota endpoints for this resource type
        if endpoints=$(get_quota_endpoints "$resource_type" "$SOURCE_REGION" 2>/dev/null); then
            # Parse endpoints (format: metric1|metric2)
            IFS='|' read -ra endpoint_array <<<"$endpoints"
            
            for endpoint in "${endpoint_array[@]}"; do
                # Add to quota specs if not already present
                quota_specs=$(echo "$quota_specs" | jq -c \
                    --arg type "$resource_type" \
                    --arg ep "$endpoint" \
                    'if any(.[]; .resourceType == $type and .endpoint == $ep) 
                     then . 
                     else . + [{resourceType: $type, endpoint: $ep}] 
                     end')
            done
        fi
    done < <(jq -r '.data[].type | ascii_downcase' "$INVENTORY_FILE" 2>/dev/null | sort -u)
    
    echo "$quota_specs"
}

# ==============================================================================
# Fetch quota for a specific service type
# ==============================================================================
fetch_service_quota() {
    local subscription_id="$1"
    local resource_type="$2"
    local region="$3"
    
    log_debug "Fetching quota for $resource_type in $region" >&2
    
    # Try Compute provider first (covers most services)
    local endpoint="https://management.azure.com/subscriptions/${subscription_id}/providers/Microsoft.Compute/locations/${region}/usages"
    local api_version="2021-07-01"
    
    local response
    if response=$(az rest --method get \
        --url "${endpoint}?api-version=${api_version}" \
        --output json 2>/dev/null); then
        
        # Filter to relevant quota for this resource type and return as array
        local filtered
        filtered=$(echo "$response" | jq -c \
            --arg type "$resource_type" \
            '[.value[]? | select(.name.localizedValue | contains($type) or .name.value | contains($type))]')
        
        # Return array (even if empty)
        echo "$filtered"
        return 0
    fi
    
    # Return empty array on failure
    echo "[]"
    return 1
}

# ==============================================================================
# Fetch all quotas for source region
# ==============================================================================
fetch_source_region_quotas() {
    # Enable quota fetching for: resource group, management group, or filtered subscriptions
    if [[ "$SCOPE_TYPE" != "rg" && "$SCOPE_TYPE" != "mg" && -z "$SUBSCRIPTIONS" ]]; then
        log_info "Quota fetching only supported for per-subscription or per-resource-group scopes"
        echo "[]" > "$QUOTA_SOURCE_FILE"
        return 0
    fi
    
    log_info "=== Fetching Source Region Quotas ==="
    
    local subscription_id
    if [[ "$SCOPE_TYPE" == "rg" ]]; then
        subscription_id="${RESOURCE_GROUP_SPEC%%:*}"
    elif [[ -n "$SUBSCRIPTIONS" ]]; then
        # Use first subscription from filtered list
        subscription_id="${SUBSCRIPTIONS%%,*}"
    else
        # For management group, use first available subscription
        subscription_id=$(az account list --query '[0].id' -o tsv 2>/dev/null) || {
            log_warning "Could not determine subscription for quota lookup"
            return 1
        }
    fi
    
    # Build unique quota list
    local quota_list
    quota_list=$(build_unique_quota_list) || {
        log_warning "Could not build quota list"
        return 1
    }
    
    local quota_count=$(echo "$quota_list" | jq '. | length')
    
    if [[ $quota_count -eq 0 ]]; then
        log_info "No quota endpoints mapped for resources in inventory"
        echo "[]" > "$QUOTA_SOURCE_FILE"
        return 0
    fi
    
    log_info "Fetching $quota_count quota metrics for subscription: $subscription_id (region: $SOURCE_REGION)"
    
    # Fetch quota data
    local quota_results="[]"
    
    while IFS= read -r quota_spec; do
        local resource_type=$(echo "$quota_spec" | jq -r '.resourceType')
        local endpoint=$(echo "$quota_spec" | jq -r '.endpoint')
        
        log_debug "Fetching quota: $resource_type ($endpoint)" >&2
        
        quota_data=$(fetch_service_quota "$subscription_id" "$resource_type" "$SOURCE_REGION" 2>/dev/null)
        
        # Validate quota_data is valid JSON before using --argjson
        if echo "$quota_data" | jq empty 2>/dev/null; then
            quota_results=$(echo "$quota_results" | jq -c \
                --arg type "$resource_type" \
                --arg region "$SOURCE_REGION" \
                --arg ep "$endpoint" \
                --argjson data "$quota_data" \
                '. + [{
                    resourceType: $type,
                    endpoint: $ep,
                    region: $region,
                    quotas: $data
                }]' 2>/dev/null) || continue
        else
            log_debug "Invalid or empty quota data for $resource_type, skipping" >&2
        fi

    done < <(echo "$quota_list" | jq -c '.[]')
    
    # Write results
        # Validate JSON before writing
        if echo "$quota_results" | jq empty 2>/dev/null; then
            echo "$quota_results" | jq '.' > "$QUOTA_SOURCE_FILE"
        else
            log_warning "Invalid JSON accumulated during quota fetch; writing empty array"
            echo "[]" > "$QUOTA_SOURCE_FILE"
        fi
    
    local result_count=$(echo "$quota_results" | jq '. | length')
    log_success "Fetched quota data for $result_count resource types"
    increment_api_call
}

# ==============================================================================
# Fetch quotas for target region (if appropriate)
# ==============================================================================
fetch_target_region_quotas() {
    # Enable quota fetching for: resource group, management group, or filtered subscriptions
    if [[ "$SCOPE_TYPE" != "rg" && "$SCOPE_TYPE" != "mg" && -z "$SUBSCRIPTIONS" ]]; then
        log_info "Target region quota fetching only supported for per-subscription or per-resource-group scopes"
        echo "[]" > "$QUOTA_TARGET_FILE"
        return 0
    fi
    
    if [[ "$TARGET_REGION" == "$SOURCE_REGION" ]]; then
        log_info "Target region same as source; skipping target region quota fetch"
        echo "[]" > "$QUOTA_TARGET_FILE"
        return 0
    fi
    
    log_info "=== Fetching Target Region Quotas ==="
    
    local subscription_id
    if [[ "$SCOPE_TYPE" == "rg" ]]; then
        subscription_id="${RESOURCE_GROUP_SPEC%%:*}"
    elif [[ -n "$SUBSCRIPTIONS" ]]; then
        # Use first subscription from filtered list
        subscription_id="${SUBSCRIPTIONS%%,*}"
    else
        subscription_id=$(az account list --query '[0].id' -o tsv 2>/dev/null) || {
            log_warning "Could not determine subscription for target region quota"
            return 1
        }
    fi
    
    log_info "Fetching quota metrics for target region: $TARGET_REGION (subscription: $subscription_id)"
    
    local quota_list
    quota_list=$(build_unique_quota_list) || return 1
    
    local quota_results="[]"
    
    while IFS= read -r quota_spec; do
        local resource_type=$(echo "$quota_spec" | jq -r '.resourceType')
        local endpoint=$(echo "$quota_spec" | jq -r '.endpoint')
        
        log_debug "Fetching target quota: $resource_type ($endpoint)" >&2
        
        quota_data=$(fetch_service_quota "$subscription_id" "$resource_type" "$TARGET_REGION" 2>/dev/null)
        
        # Validate quota_data is valid JSON before using --argjson
        if echo "$quota_data" | jq empty 2>/dev/null; then
            quota_results=$(echo "$quota_results" | jq -c \
                --arg type "$resource_type" \
                --arg region "$TARGET_REGION" \
                --arg ep "$endpoint" \
                --argjson data "$quota_data" \
                '. + [{
                    resourceType: $type,
                    endpoint: $ep,
                    region: $region,
                    quotas: $data
                }]' 2>/dev/null) || continue
        else
            log_debug "Invalid or empty quota data for $resource_type, skipping" >&2
        fi
    done < <(echo "$quota_list" | jq -c '.[]')
    
        # Validate JSON before writing
        if echo "$quota_results" | jq empty 2>/dev/null; then
            echo "$quota_results" | jq '.' > "$QUOTA_TARGET_FILE"
        else
            log_warning "Invalid JSON accumulated during target quota fetch; writing empty array"
            echo "[]" > "$QUOTA_TARGET_FILE"
        fi
    
    local result_count=$(echo "$quota_results" | jq '. | length')
    log_success "Fetched quota data for $result_count resource types in target region"
    increment_api_call
}

# ==============================================================================
# Generate quota summary CSV
# ==============================================================================
generate_quota_summary() {
    log_info "Generating quota summary..."
    
    if [[ ! -f "$QUOTA_SOURCE_FILE" ]]; then
        log_debug "Quota source file not found; skipping summary" >&2
        return 0
    fi
    
    # Create CSV with headers
    cat > "$QUOTA_SUMMARY_FILE" << 'EOF'
region,resourceType,quotaMetric,limit,currentUsage,availableQuota,percentUsed
EOF
    
    # Validate and process source region quotas
    if jq empty "$QUOTA_SOURCE_FILE" 2>/dev/null; then
        local source_count=$(jq '. | length' "$QUOTA_SOURCE_FILE" 2>/dev/null || echo 0)
        if [[ $source_count -gt 0 ]]; then
            jq -r '.[] | 
                .region as $region |
                .resourceType as $type |
                .quotas[]? |
                [
                    $region,
                    $type,
                    .name.localizedValue // .name.value,
                    .limit,
                    .currentValue,
                    (.limit - .currentValue),
                    (((.currentValue / .limit) * 100) | round)
                ] | @csv' "$QUOTA_SOURCE_FILE" 2>/dev/null >> "$QUOTA_SUMMARY_FILE" || true
        fi
    else
        log_debug "Quota source file is empty or invalid JSON" >&2
    fi
    
    # Process target region quotas if available
    if [[ -f "$QUOTA_TARGET_FILE" ]] && jq empty "$QUOTA_TARGET_FILE" 2>/dev/null; then
        local target_count=$(jq '. | length' "$QUOTA_TARGET_FILE" 2>/dev/null || echo 0)
        if [[ $target_count -gt 0 ]]; then
            jq -r '.[] | 
                .region as $region |
                .resourceType as $type |
                .quotas[]? |
                [
                    $region,
                    $type,
                    .name.localizedValue // .name.value,
                    .limit,
                    .currentValue,
                    (.limit - .currentValue),
                    (((.currentValue / .limit) * 100) | round)
                ] | @csv' "$QUOTA_TARGET_FILE" 2>/dev/null >> "$QUOTA_SUMMARY_FILE" || true
        fi
    fi
    
    local line_count=$(wc -l < "$QUOTA_SUMMARY_FILE")
    log_success "Quota summary created: $QUOTA_SUMMARY_FILE ($((line_count - 1)) quota metrics)"
}

# ==============================================================================
# Check quota availability for a specific resource
# ==============================================================================
check_quota_available() {
    local subscription_id="$1"
    local resource_type="$2"
    local region="$3"
    local count="${4:-1}"
    
    log_debug "Checking quota availability: $resource_type in $region (count: $count)" >&2
    
    # Get quota for resource type
    if quota_data=$(fetch_service_quota "$subscription_id" "$resource_type" "$region" 2>/dev/null); then
        # Check if available quota >= requested count
        local available=$(echo "$quota_data" | jq -r '.limit - .currentValue' 2>/dev/null | head -n 1)
        
        if [[ -z "$available" ]] || [[ $available -le 0 ]]; then
            echo "insufficient"
            return 1
        elif [[ $available -ge $count ]]; then
            echo "sufficient"
            return 0
        else
            echo "partial"
            return 1
        fi
    fi
    
    echo "unknown"
    return 1
}

# ==============================================================================
# Get quota statistics by region
# ==============================================================================
quota_stats_by_region() {
    local quota_file="$1"
    
    if [[ ! -f "$quota_file" ]]; then
        return 1
    fi
    
    jq -r '.[] |
        "\(.region): \(.resourceType) - Used: \(.quotas[0].currentValue // "N/A") / \(.quotas[0].limit // "N/A")"' \
        "$quota_file" | sort -u
}

# ==============================================================================
# Export for use in subshells
# ==============================================================================
export -f get_quota_endpoints
export -f fetch_subscription_quota
export -f fetch_usage_metrics
export -f build_unique_quota_list
export -f fetch_service_quota
export -f fetch_source_region_quotas
export -f fetch_target_region_quotas
export -f generate_quota_summary
export -f check_quota_available
export -f quota_stats_by_region
