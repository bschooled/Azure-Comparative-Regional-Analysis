#!/usr/bin/env bash
# ==============================================================================
# Data Processing - Summarization and Tuple Extraction
# ==============================================================================

# Output files
SUMMARY_FILE="${OUTPUT_DIR}/source_inventory_summary.csv"
TUPLES_FILE="${OUTPUT_DIR}/unique_tuples.json"

# ==============================================================================
# Summarize inventory to CSV
# ==============================================================================
summarize_inventory() {
    log_info "Summarizing inventory..."
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        return 1
    fi
    
    # Create summary CSV with counts by type, sku, and relevant properties
    jq -r '.data | 
        group_by(.subscriptionId, .resourceGroup, .location, .type, .sku, .vmSize, .diskSku, .diskSizeGB) |
        map({
            subscriptionId: .[0].subscriptionId,
            resourceGroup: .[0].resourceGroup,
            location: .[0].location,
            type: .[0].type,
            sku: .[0].sku,
            vmSize: .[0].vmSize,
            diskSku: .[0].diskSku,
            diskSizeGB: .[0].diskSizeGB,
            count: length
        }) |
        (["subscriptionId","resourceGroup","location","type","sku","vmSize","diskSku","diskSizeGB","count"] | @csv),
        (.[] | [.subscriptionId, .resourceGroup, .location, .type, .sku, .vmSize, .diskSku, .diskSizeGB, .count] | @csv)
    ' "$INVENTORY_FILE" > "$SUMMARY_FILE"
    
    local line_count=$(wc -l < "$SUMMARY_FILE")
    log_success "Inventory summary created: $SUMMARY_FILE ($(($line_count - 1)) unique combinations)"
}

# ==============================================================================
# Derive unique resource tuples for pricing lookup
# ==============================================================================
derive_unique_tuples() {
    log_info "Deriving unique resource tuples for pricing lookup..."
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        return 1
    fi
    
    # Extract unique tuples with relevant fields for pricing lookup
    jq -r '.data |
        map({
            type: .type,
            sku: .sku,
            vmSize: .vmSize,
            diskSku: .diskSku,
            diskSizeGB: .diskSizeGB,
            tier: .tier,
            capacity: .capacity,
            storageAccountKind: .storageAccountKind,
            region: .location,
            quota: null,
            quotaUsage: null
        }) |
        unique_by(.type, .sku, .vmSize, .diskSku, .diskSizeGB, .tier, .capacity, .storageAccountKind)
    ' "$INVENTORY_FILE" > "$TUPLES_FILE"
    
    local tuple_count=$(jq '. | length' "$TUPLES_FILE")
    log_success "Derived $tuple_count unique resource tuples"
}

# ==============================================================================
# Classify resource type for pricing lookup
# ==============================================================================
classify_resource_type() {
    local resource_type="$1"
    
    case "$resource_type" in
        Microsoft.Compute/virtualMachines)
            echo "vm"
            ;;
        Microsoft.Compute/disks)
            echo "disk"
            ;;
        Microsoft.Storage/storageAccounts)
            echo "storage"
            ;;
        Microsoft.Network/loadBalancers)
            echo "loadbalancer"
            ;;
        Microsoft.Network/publicIPAddresses)
            echo "publicip"
            ;;
        Microsoft.Network/natGateways)
            echo "natgateway"
            ;;
        Microsoft.Network/applicationGateways)
            echo "appgateway"
            ;;
        Microsoft.Sql/servers/databases)
            echo "sqldatabase"
            ;;
        Microsoft.DBforPostgreSQL/flexibleServers)
            echo "postgresql"
            ;;
        Microsoft.DBforMySQL/flexibleServers)
            echo "mysql"
            ;;
        Microsoft.DocumentDB/databaseAccounts)
            echo "cosmosdb"
            ;;
        Microsoft.Cache/redis)
            echo "redis"
            ;;
        Microsoft.KeyVault/vaults)
            echo "keyvault"
            ;;
        *)
            echo "other"
            ;;
    esac
}

# ==============================================================================
# Check if resource type has direct pricing meter
# ==============================================================================
has_direct_meter() {
    local resource_type="$1"
    
    # Resources without direct meters
    case "$resource_type" in
        Microsoft.Resources/resourceGroups|\
        Microsoft.Authorization/roleAssignments|\
        Microsoft.Authorization/policyAssignments|\
        Microsoft.ManagedIdentity/userAssignedIdentities)
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# ==============================================================================
# Enrich tuples with quota data
# ==============================================================================
enrich_tuples_with_quota() {
    log_info "Enriching tuples with quota information..."
    
    if [[ ! -f "$TUPLES_FILE" ]]; then
        log_error "Tuples file not found: $TUPLES_FILE"
        return 1
    fi
    
    if [[ ! -f "$QUOTA_SOURCE_FILE" ]]; then
        log_debug "Quota source file not found; skipping quota enrichment" >&2
        return 0
    fi
    
    # Create a temporary lookup file from quota data indexed by resource type
    local quota_lookup=$(jq -c 'reduce .[] as $item ({}; 
        .[$item.resourceType | ascii_downcase] = $item.quotas[0])' "$QUOTA_SOURCE_FILE")
    
    # Enrich tuples with quota data
    local enriched=$(jq -c \
        --argjson quotas "$quota_lookup" \
        '.[] | 
        .quota = $quotas[.type | ascii_downcase] // null |
        .quotaUsage = if .quota != null then .quota.currentValue else null end' \
        "$TUPLES_FILE")
    
    # Convert back to array format and write
    echo "[$(echo "$enriched" | paste -sd, -)]" | jq '.' > "$TUPLES_FILE" 2>/dev/null || {
        log_warning "Could not enrich tuples with quota data; keeping original format"
        return 1
    }
    
    log_success "Tuples enriched with quota data"
    return 0
}

# ==============================================================================
# Extract Top 5 resources needing quota by count
# ==============================================================================
get_top_quota_resources() {
    log_info "Getting top 5 resources requiring quota in source region..."
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        return 1
    fi
    
    # Get top 5 resource types by count, filter to those that need quota
    jq -r '.data |
        map(select(.type | startswith("microsoft.compute") or startswith("microsoft.network") or startswith("microsoft.storage"))) |
        group_by(.type) |
        map({
            type: .[0].type,
            count: length,
            region: .[0].location
        }) |
        sort_by(-.count) |
        .[:5]' "$INVENTORY_FILE"
}

# ==============================================================================
# Get summary of resources needing quota in target region
# ==============================================================================
get_quota_summary_for_target() {
    log_info "Getting quota summary for target region resources..."
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        return 1
    fi
    
    # Count resources by type that may need quota in target
    jq '.data |
        map(select(.type | startswith("microsoft.compute") or startswith("microsoft.network") or startswith("microsoft.storage"))) |
        group_by(.type) |
        map({
            type: .[0].type,
            count: length
        }) |
        sort_by(-.count)' "$INVENTORY_FILE"
}

export -f summarize_inventory
export -f derive_unique_tuples
export -f classify_resource_type
export -f has_direct_meter
export -f enrich_tuples_with_quota
export -f get_top_quota_resources
export -f get_quota_summary_for_target
