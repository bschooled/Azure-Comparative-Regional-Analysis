#!/usr/bin/env bash
# ==============================================================================
# Comparative Regional Analysis - Cross-Region Availability Tables
# ==============================================================================

# Output files
COMPARATIVE_TABLE_FILE="${OUTPUT_DIR}/service_availability_comparison.csv"
COMPARATIVE_JSON_FILE="${OUTPUT_DIR}/service_availability_comparison.json"

# ==============================================================================
# Generate comparative availability table for all services
# ==============================================================================
generate_comparative_tables() {
    log_info "Generating comparative regional availability tables..."
    
    if [[ ! -f "$AVAILABILITY_FILE" ]]; then
        log_error "Availability file not found: $AVAILABILITY_FILE"
        return 1
    fi
    
    # Get unique service types
    local service_types=$(jq -r '.[] | .type' "$AVAILABILITY_FILE" | sort -u)
    
    if [[ -z "$service_types" ]]; then
        log_warning "No service types found in availability data"
        return 1
    fi
    
    # Generate CSV comparative table
    generate_comparative_csv "$service_types"
    
    # Generate JSON comparative table with richer details
    generate_comparative_json "$service_types"
    
    local table_count=$(echo "$service_types" | wc -l)
    log_success "Generated comparative tables for $table_count service types"
}

# ==============================================================================
# Generate CSV comparative table
# ==============================================================================
generate_comparative_csv() {
    local service_types="$1"
    local regions_to_check=("$SOURCE_REGION" "$TARGET_REGION")
    
    # Build CSV header with all regions
    local header="ServiceType,SKU/Name"
    for region in "${regions_to_check[@]}"; do
        header="${header},${region}Available,${region}Details"
    done
    echo "$header" > "$COMPARATIVE_TABLE_FILE"
    
    # Get all unique SKUs per service
    while IFS= read -r service_type; do
        # Get unique SKUs/names for this service type
        local skus=$(jq -r ".[] | 
            select(.type == \"$service_type\") | 
            .armSkuName // .sku // .name // \"N/A\"" "$AVAILABILITY_FILE" | sort -u)
        
        if [[ -z "$skus" ]]; then
            skus="N/A"
        fi
        
        while IFS= read -r sku; do
            local csv_line="$service_type,\"$sku\""
            
            # For each region, check availability
            for region in "${regions_to_check[@]}"; do
                local region_data=$(jq -c ".[] | 
                    select(.type == \"$service_type\" and 
                           (.armSkuName // .sku // .name // \"N/A\") == \"$sku\" and
                           .targetRegion == \"$region\")" "$AVAILABILITY_FILE" | head -n1)
                
                if [[ -z "$region_data" ]]; then
                    # Fallback: check without targeting specific region (for source region)
                    if [[ "$region" == "$SOURCE_REGION" ]]; then
                        # If in source inventory, assume available
                        csv_line="${csv_line},YES,Found in inventory"
                    else
                        csv_line="${csv_line},UNKNOWN,Not checked"
                    fi
                else
                    local available=$(echo "$region_data" | jq -r '.available')
                    local details=""
                    
                    if [[ "$available" == "true" ]]; then
                        details="Available"
                    else
                        local reason=$(echo "$region_data" | jq -r '.reason // "Not available"')
                        details="$reason"
                    fi
                    
                    csv_line="${csv_line},$available,\"$details\""
                fi
            done
            
            echo "$csv_line" >> "$COMPARATIVE_TABLE_FILE"
        done <<< "$skus"
    done <<< "$service_types"
    
    log_info "CSV comparative table created: $COMPARATIVE_TABLE_FILE"
}

# ==============================================================================
# Generate JSON comparative table with rich details
# ==============================================================================
generate_comparative_json() {
    local service_types="$1"
    local json_output="[]"
    
    while IFS= read -r service_type; do
        # Get unique tuples for this service
        local tuples=$(jq -r "[.[] | 
            select(.type == \"$service_type\") | 
            {armSkuName: (.armSkuName // .sku // .name // \"N/A\"), 
             targetRegion: .targetRegion}] | 
            unique_by(.armSkuName, .targetRegion)" "$AVAILABILITY_FILE")
        
        # Get inventory count for this service type
        local inventory_count=$(jq "[.[] | select(.type == \"$service_type\")] | length" "$INVENTORY_FILE" 2>/dev/null || echo "0")
        
        # Build service entry
        local service_entry="{
            \"serviceType\": \"$service_type\",
            \"inventoryCount\": $inventory_count,
            \"availability\": []
        }"
        
        # Add availability info for each region
        local availability_array="[]"
        
        # Check source region (from inventory)
        local source_count=$(jq "[.[] | select(.type == \"$service_type\" and .location == \"$SOURCE_REGION\")] | length" "$INVENTORY_FILE" 2>/dev/null || echo "0")
        local source_entry="{
            \"region\": \"$SOURCE_REGION\",
            \"available\": true,
            \"resourceCount\": $source_count,
            \"evidence\": \"Found in source region inventory\"
        }"
        availability_array=$(echo "$availability_array" | jq -c ". += [$source_entry]")
        
        # Check target region
        local target_entries=$(jq ".[] | 
            select(.type == \"$service_type\" and .targetRegion == \"$TARGET_REGION\")" "$AVAILABILITY_FILE" | jq -s 'map({
                armSkuName: (.armSkuName // .sku // .name // "N/A"),
                available: (.available // false),
                restrictions: (.restrictions // [])
            })')
        
        if [[ -n "$target_entries" && "$target_entries" != "null" && "$target_entries" != "[]" ]]; then
            availability_array=$(echo "$availability_array" | jq -c --argjson entries "$target_entries" --arg region "$TARGET_REGION" '
                . + [{
                    region: $region,
                    available: (([$entries[] | select(.available == true)] | length) > 0),
                    details: $entries
                }]
            ')
        else
            availability_array=$(echo "$availability_array" | jq -c ". += [{
                \"region\": \"$TARGET_REGION\",
                \"available\": false,
                \"evidence\": \"Resource type not available\"
            }]")
        fi
        
        service_entry=$(echo "$service_entry" | jq -c --argjson avail "$availability_array" '.availability = $avail')
        json_output=$(echo "$json_output" | jq -c ". += [$service_entry]")
        
    done <<< "$service_types"
    
    echo "$json_output" | jq '.' > "$COMPARATIVE_JSON_FILE"
    log_info "JSON comparative table created: $COMPARATIVE_JSON_FILE"
}

# ==============================================================================
# Generate summary statistics table
# ==============================================================================
generate_availability_summary() {
    local summary_file="${OUTPUT_DIR}/availability_summary.txt"
    
    log_info "Generating availability summary..."
    
    {
        echo "================================================================================"
        echo "AZURE REGIONAL AVAILABILITY COMPARISON"
        echo "================================================================================"
        echo ""
        echo "Source Region: $SOURCE_REGION"
        echo "Target Region: $TARGET_REGION"
        echo "Report Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
        echo ""
        echo "================================================================================"
        echo "INVENTORY SUMMARY"
        echo "================================================================================"
        
        # Total resources
        local total_resources=$(jq '.data | length' "$INVENTORY_FILE")
        echo "Total Resources in Source Region: $total_resources"
        echo ""
        
        # Resources by type
        echo "Resources by Type:"
        jq -r '.data | group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count) | .[] | "  \(.type): \(.count)"' "$INVENTORY_FILE"
        echo ""
        
        echo "================================================================================"
        echo "AVAILABILITY IN TARGET REGION"
        echo "================================================================================"
        
        local available_count=$(jq '[.[] | select(.available == true)] | length' "$AVAILABILITY_FILE")
        local unavailable_count=$(jq '[.[] | select(.available == false)] | length' "$AVAILABILITY_FILE")
        local total_checked=$(jq '. | length' "$AVAILABILITY_FILE")
        
        echo "Total Service Types Checked: $total_checked"
        echo "Available in Target Region:  $available_count"
        echo "Unavailable in Target Region: $unavailable_count"
        echo ""
        
        if [[ $unavailable_count -gt 0 ]]; then
            echo "Services NOT Available in Target Region:"
            jq -r '.[] | select(.available == false) | "  \(.type): \(.reason // "Not available")"' "$AVAILABILITY_FILE" | sort -u
            echo ""
        fi
        
        echo "================================================================================"
        echo "RESTRICTIONS AND NOTES"
        echo "================================================================================"
        
        local restricted=$(jq '[.[] | select(.restrictions != null and (.restrictions | length) > 0)] | length' "$AVAILABILITY_FILE")
        
        if [[ $restricted -gt 0 ]]; then
            echo "Services with Restrictions in Target Region: $restricted"
            jq -r '.[] | select(.restrictions != null and (.restrictions | length) > 0) | "  \(.type) (\(.armSkuName // .sku)): \(.restrictions | map(.type // .description) | join(", "))"' "$AVAILABILITY_FILE"
            echo ""
        fi
        
        echo "================================================================================"
        
    } | tee "$summary_file"
    
    log_info "Availability summary created: $summary_file"
}

# ==============================================================================
# Display comparative table to console
# ==============================================================================
display_comparative_summary() {
    log_info ""
    log_info "=== COMPARATIVE AVAILABILITY SUMMARY ==="
    log_info ""
    
    # Service availability overview
    local total_services=$(jq '.[] | .type' "$AVAILABILITY_FILE" | sort -u | wc -l)
    local available_services=$(jq '[.[] | select(.available == true)] | .[].type' "$AVAILABILITY_FILE" | sort -u | wc -l)
    
    log_info "Service Types Analyzed: $total_services"
    log_info "Available in $TARGET_REGION: $available_services"
    log_info ""
    log_info "See detailed reports:"
    log_info "  - CSV Table: $COMPARATIVE_TABLE_FILE"
    log_info "  - JSON Table: $COMPARATIVE_JSON_FILE"
    log_info "  - Summary: ${OUTPUT_DIR}/availability_summary.txt"
}
