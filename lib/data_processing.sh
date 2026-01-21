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
            region: .location
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
