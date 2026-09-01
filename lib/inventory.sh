#!/usr/bin/env bash
# ==============================================================================
# Resource Inventory via Azure Resource Graph (ARG)
# ==============================================================================

# Output files
INVENTORY_FILE="${OUTPUT_DIR}/source_inventory.json"

# ==============================================================================
# Build KQL query for resource inventory
# ==============================================================================
build_inventory_kql() {
    local source_region="$1"
    local resource_types_filter="$2"
    
    local kql="Resources
| where tolower(location) == tolower('${source_region}')"
    
    # Add resource type filter if specified
    if [[ -n "$resource_types_filter" ]]; then
        # Convert CSV to KQL array format
        local types_array=$(echo "$resource_types_filter" | sed "s/,/', '/g")
        kql="$kql
| where type in~ ('${types_array}')"
    fi
    
    kql="$kql
| project id, name, type, location, subscriptionId, resourceGroup,
          sku = tostring(sku.name),
          vmSize = tostring(properties.hardwareProfile.vmSize),
          diskSku = iff(type =~ 'microsoft.compute/disks', tostring(sku.name), ''),
          diskSizeGB = iff(type =~ 'microsoft.compute/disks', toint(properties.diskSizeGB), int(null)),
          storageAccountKind = iff(type =~ 'microsoft.storage/storageaccounts', tostring(kind), ''),
          tier = tostring(sku.tier),
          capacity = tostring(sku.capacity),
          properties"
    
    echo "$kql"
}

# ==============================================================================
# Execute Azure Resource Graph query
# ==============================================================================
run_resource_graph_query() {
    log_info "Building Azure Resource Graph query..."
    
    local kql=$(build_inventory_kql "$SOURCE_REGION" "$RESOURCE_TYPES")
    log_debug "KQL Query:\n$kql"
    
    log_info "Executing Azure Resource Graph query for source region: $SOURCE_REGION"
    
    # Build scope arguments
    local scope_args=""
    
    case "$SCOPE_TYPE" in
        all)
            # No additional scope args needed for tenant-wide
            log_info "Querying all accessible subscriptions"
            ;;
        mg)
            scope_args="--management-groups $MANAGEMENT_GROUP_ID"
            log_info "Querying management group: $MANAGEMENT_GROUP_ID"
            ;;
        rg)
            # Parse subscription ID from resource group spec (format: subId:rgName)
            local sub_id="${RESOURCE_GROUP_SPEC%%:*}"
            scope_args="--subscriptions $sub_id"
            log_info "Querying resource group: $RESOURCE_GROUP_SPEC"
            ;;
    esac
    
    # Override with explicit subscriptions if provided
    if [[ -n "$SUBSCRIPTIONS" ]]; then
        scope_args="--subscriptions $SUBSCRIPTIONS"
        log_info "Using explicit subscription list: $SUBSCRIPTIONS"
    fi
    
    # Execute ARG query
    log_info "Running ARG query..."
    if az graph query -q "$kql" $scope_args --output json > "$INVENTORY_FILE" 2>> "${LOG_FILE}"; then
        local resource_count=$(jq -r '.data | length' "$INVENTORY_FILE")
        log_success "ARG query completed. Found $resource_count resources"
        
        # If resource group scope, filter further by resource group name
        if [[ "$SCOPE_TYPE" == "rg" ]]; then
            local rg_name="${RESOURCE_GROUP_SPEC#*:}"
            log_info "Filtering to resource group: $rg_name"
            jq ".data |= map(select(.resourceGroup == \"$rg_name\"))" "$INVENTORY_FILE" > "${INVENTORY_FILE}.tmp"
            mv "${INVENTORY_FILE}.tmp" "$INVENTORY_FILE"
            resource_count=$(jq -r '.data | length' "$INVENTORY_FILE")
            log_info "After resource group filter: $resource_count resources"
        fi
        
        increment_api_call
    else
        log_error "ARG query failed. Check log file for details."
        exit 1
    fi
}

# ==============================================================================
# Ingest a provided inventory file (supports multiple formats)
# ==============================================================================
ingest_inventory_file() {
    local input_file="$INVENTORY_INPUT_FILE"
    if [[ -z "$input_file" ]]; then
        log_error "No inventory file provided"
        return 1
    fi
    if [[ ! -f "$input_file" ]]; then
        log_error "Specified inventory file not found: $input_file"
        return 1
    fi

    log_info "Ingesting inventory from file: $input_file"

    # Detect format and transform to ARG-compatible schema with .data array
    # Supported inputs:
    # 1) { data: [...] }  (ARG-compatible)
    # 2) { resources: [...], metadata: {...} }  (generator format)
    # 3) [ ... ]  (raw array of resource entries)

    local format
    format=$(jq -r 'if has("data") then "data"
                   elif has("resources") then "resources"
                   elif type == "array" then "array"
                   else "unknown" end' "$input_file" 2>/dev/null || echo "unknown")

    case "$format" in
        data)
            # Already ARG-compatible; copy as-is
            cp "$input_file" "$INVENTORY_FILE"
            ;;
        resources)
            # Transform generator format into ARG-compatible .data entries
            jq -c '{data: (.resources | map({
                id: (.id // .name // "id"),
                name: (.name // "resource"),
                type: ( .type | sub("^microsoft"; "Microsoft") ),
                location: (.location // (.region // .metadata.source_region // "")),
                subscriptionId: ("00000000-0000-0000-0000-000000000000"),
                resourceGroup: ("TestRG"),
                sku: ( .sku // .diskSku // "" ),
                vmSize: (.vmSize // ""),
                diskSku: (.diskSku // ""),
                diskSizeGB: (.diskSizeGB // null),
                storageAccountKind: (.storageAccountKind // ""),
                tier: (.tier // ""),
                capacity: (.capacity // ""),
                properties: {}
            }))}' "$input_file" > "$INVENTORY_FILE"
            ;;
        array)
            # Wrap array into { data: [...] } and normalize casing
            jq -c '{data: ( . | map({
                id: (.id // .name // "id"),
                name: (.name // "resource"),
                type: ( .type | sub("^microsoft"; "Microsoft") ),
                location: (.location // (.region // "")),
                subscriptionId: ("00000000-0000-0000-0000-000000000000"),
                resourceGroup: ("TestRG"),
                sku: ( .sku // .diskSku // "" ),
                vmSize: (.vmSize // ""),
                diskSku: (.diskSku // ""),
                diskSizeGB: (.diskSizeGB // null),
                storageAccountKind: (.storageAccountKind // ""),
                tier: (.tier // ""),
                capacity: (.capacity // ""),
                properties: {}
            }))}' "$input_file" > "$INVENTORY_FILE"
            ;;
        *)
            log_error "Unsupported inventory format; expected keys 'data' or 'resources' or a top-level array"
            return 1
            ;;
    esac

    local resource_count=$(jq -r '.data | length' "$INVENTORY_FILE" 2>/dev/null || echo 0)
    log_success "Ingested $resource_count resources from file"
}

# ==============================================================================
# Get resource count by type
# ==============================================================================
get_resource_count_by_type() {
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found: $INVENTORY_FILE"
        return 1
    fi
    
    jq -r '.data | group_by(.type) | map({type: .[0].type, count: length}) | .[]' "$INVENTORY_FILE"
}
