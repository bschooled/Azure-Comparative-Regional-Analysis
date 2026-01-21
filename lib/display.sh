#!/usr/bin/env bash
# ==============================================================================
# Shell Display and Formatting Utilities
# ==============================================================================

# ==============================================================================
# Print colored box with title
# ==============================================================================
print_box() {
    local title="$1"
    local width=80
    
    printf "%s" "${BLUE}"
    printf "╔"; printf '═%.0s' $(seq 1 $((width - 2))); printf "╗\n"
    printf "║ %-*s ║\n" $((width - 3)) "$title"
    printf "╠"; printf '═%.0s' $(seq 1 $((width - 2))); printf "╣\n"
    printf "%s" "${NC}"
}

# ==============================================================================
# Print box end
# ==============================================================================
print_box_end() {
    local width=80
    printf "%s" "${BLUE}"
    printf "╚"; printf '═%.0s' $(seq 1 $((width - 2))); printf "╝\n"
    printf "%s\n" "${NC}"
}

# ==============================================================================
# Print section divider
# ==============================================================================
print_divider() {
    printf "%s" "${BLUE}"
    printf "├"; printf '─%.0s' $(seq 1 78); printf "┤\n"
    printf "%s" "${NC}"
}

# ==============================================================================
# Print key-value pair
# ==============================================================================
print_kv() {
    local key="$1"
    local value="$2"
    local color="${3:-${GREEN}}"
    printf "  ${color}%-40s${NC} %s\n" "$key:" "$value"
}

# ==============================================================================
# Print warning item
# ==============================================================================
print_warning_item() {
    local item="$1"
    printf "  ${YELLOW}⚠${NC}  %s\n" "$item"
}

# ==============================================================================
# Print success item
# ==============================================================================
print_success_item() {
    local item="$1"
    printf "  ${GREEN}✓${NC}  %s\n" "$item"
}

# ==============================================================================
# Print error item
# ==============================================================================
print_error_item() {
    local item="$1"
    printf "  ${RED}✗${NC}  %s\n" "$item"
}

# ==============================================================================
# Print info item
# ==============================================================================
print_info_item() {
    local item="$1"
    printf "  ${BLUE}ℹ${NC}  %s\n" "$item"
}

# ==============================================================================
# Display inventory summary to shell
# ==============================================================================
display_inventory_summary() {
    print_box "INVENTORY SUMMARY"
    
    if [[ ! -f "$INVENTORY_FILE" ]]; then
        log_error "Inventory file not found"
        return 1
    fi
    
    # Total resources
    local total_resources=$(jq '.data | length' "$INVENTORY_FILE" 2>/dev/null || echo "0")
    print_kv "Total Resources" "$total_resources" "${GREEN}"
    
    # Top resource types
    echo ""
    printf "  ${BLUE}Resource Types:${NC}\n"
    jq -r '.data | map(select(.type != null)) | group_by(.type) | map({type: .[0].type, count: length}) | sort_by(-.count) | .[:5] | .[] | "    \(.type): \(.count)"' "$INVENTORY_FILE" 2>/dev/null | while read -r line; do
        printf "    %s\n" "$line"
    done
    
    print_box_end
}

# ==============================================================================
# Display pricing summary to shell
# ==============================================================================
display_pricing_summary() {
    if [[ ! -f "$PRICE_LOOKUP_FILE" ]]; then
        return 1
    fi
    
    print_box "PRICING INFORMATION"
    
    # Count priced resources
    local priced_count=$(($(wc -l < "$PRICE_LOOKUP_FILE") - 1))
    print_kv "Priced Resources" "$priced_count" "${GREEN}"
    
    # Check for unpriced
    if [[ -f "$UNPRICED_FILE" ]]; then
        local unpriced_count=$(jq '. | length' "$UNPRICED_FILE" 2>/dev/null || echo "0")
        if [[ $unpriced_count -gt 0 ]]; then
            print_warning_item "$unpriced_count resources without pricing meter"
        fi
    fi
    
    print_box_end
}

# ==============================================================================
# Display availability summary to shell
# ==============================================================================
display_availability_summary() {
    if [[ ! -f "$AVAILABILITY_FILE" ]]; then
        return 1
    fi
    
    print_box "AVAILABILITY IN TARGET REGION: $TARGET_REGION"
    
    # Count available and unavailable
    local available=$(jq '[.[] | select(.available == true)] | length' "$AVAILABILITY_FILE" 2>/dev/null || echo "0")
    local unavailable=$(jq '[.[] | select(.available == false)] | length' "$AVAILABILITY_FILE" 2>/dev/null || echo "0")
    local total=$((available + unavailable))
    
    print_kv "Service Types Checked" "$total" "${BLUE}"
    print_kv "Available in Target" "$available" "${GREEN}"
    
    if [[ $unavailable -gt 0 ]]; then
        print_kv "Unavailable in Target" "$unavailable" "${RED}"
        
        echo ""
        printf "  ${YELLOW}Services NOT Available:${NC}\n"
        jq -r '.[] | select(.available == false) | "    - \(.type)"' "$AVAILABILITY_FILE" 2>/dev/null | sort -u | head -10 | while read -r line; do
            printf "%s\n" "$line"
        done
    else
        print_success_item "All service types available in target region"
    fi
    
    # Check for restrictions
    local restricted=$(jq '[.[] | select(.restrictions != null and (.restrictions | length) > 0)] | length' "$AVAILABILITY_FILE" 2>/dev/null || echo "0")
    if [[ $restricted -gt 0 ]]; then
        echo ""
        print_warning_item "$restricted service types have restrictions in target region"
    fi
    
    print_box_end
}

# ==============================================================================
# Display comparative analysis summary to shell
# ==============================================================================
display_comparative_summary_shell() {
    if [[ ! -f "$COMPARATIVE_JSON_FILE" ]]; then
        return 1
    fi
    
    print_box "COMPARATIVE REGIONAL ANALYSIS"
    
    # Count services by availability
    local total_services=$(jq '. | length' "$COMPARATIVE_JSON_FILE" 2>/dev/null || echo "0")
    print_kv "Service Types Analyzed" "$total_services" "${BLUE}"
    
    # Services available in both regions
    local available_both=$(jq '[.[] | select(.availability[0].available == true and .availability[1].available == true)] | length' "$COMPARATIVE_JSON_FILE" 2>/dev/null || echo "0")
    if [[ $available_both -gt 0 ]]; then
        print_success_item "$available_both services available in both regions"
    fi
    
    # Services only in source
    local source_only=$(jq '[.[] | select(.availability[0].available == true and (.availability[1].available == false or .availability[1].available == null))] | length' "$COMPARATIVE_JSON_FILE" 2>/dev/null || echo "0")
    if [[ $source_only -gt 0 ]]; then
        print_warning_item "$source_only services only in source region (migration needed)"
    fi
    
    # Total inventory resources
    local total_inventory=$(jq '[.[] | .inventoryCount] | add' "$COMPARATIVE_JSON_FILE" 2>/dev/null || echo "0")
    print_kv "Total Resources in Source" "$total_inventory" "${BLUE}"
    
    print_box_end
}

# ==============================================================================
# Display execution statistics
# ==============================================================================
display_execution_stats() {
    print_box "EXECUTION STATISTICS"
    
    print_kv "Source Region" "$SOURCE_REGION" "${GREEN}"
    print_kv "Target Region" "$TARGET_REGION" "${GREEN}"
    print_kv "Scope" "$SCOPE_TYPE" "${BLUE}"
    
    if [[ -n "$SUBSCRIPTIONS" ]]; then
        print_kv "Subscriptions" "$SUBSCRIPTIONS" "${BLUE}"
    fi
    
    print_kv "Parallel Concurrency" "$PARALLEL" "${BLUE}"
    
    if [[ -n "$API_CALL_COUNT" && $API_CALL_COUNT -gt 0 ]]; then
        echo ""
        printf "  ${BLUE}API Activity:${NC}\n"
        print_kv "  API Calls Made" "$API_CALL_COUNT" "${BLUE}"
        print_kv "  Cache Hits" "$CACHE_HIT_COUNT" "${GREEN}"
        
        if [[ $API_CALL_COUNT -gt 0 ]]; then
            local total=$((API_CALL_COUNT + CACHE_HIT_COUNT))
            local hit_rate=$((CACHE_HIT_COUNT * 100 / total))
            print_kv "  Cache Hit Rate" "${hit_rate}%" "${GREEN}"
        fi
    fi
    
    print_kv "Execution Errors" "$ERROR_COUNT" "${RED}"
    print_kv "Execution Warnings" "$WARNING_COUNT" "${YELLOW}"
    
    print_box_end
}

# ==============================================================================
# Display quota summary to shell
# ==============================================================================
display_quota_summary() {
    if [[ ! -f "$QUOTA_SUMMARY_FILE" ]]; then
        return 1
    fi
    
    print_box "SERVICE QUOTA ANALYSIS"
    
    # Count total resources needing quota in source region
    local resources_needing_quota=$(jq '.data | 
        map(select(.type | startswith("microsoft.compute") or startswith("microsoft.network") or startswith("microsoft.storage"))) | 
        length' "$INVENTORY_FILE" 2>/dev/null || echo "0")
    
    print_kv "Resources Needing Quota (Source)" "$resources_needing_quota" "${BLUE}"
    
    # Show top 5 resources by count
    if [[ $resources_needing_quota -gt 0 ]]; then
        echo ""
        printf "  ${BLUE}Top 5 Resources in Source Region:${NC}\n"
        
        jq '.data |
            map(select(.type | startswith("microsoft.compute") or startswith("microsoft.network") or startswith("microsoft.storage"))) |
            group_by(.type) |
            map({
                type: (.[0].type | split("/")[1] // .[0].type),
                count: length
            }) |
            sort_by(-.count) |
            .[:5]' "$INVENTORY_FILE" 2>/dev/null | \
        jq -r '.[] | "    \(.type): \(.count) resource(s)"' | while read -r line; do
            printf "    %s\n" "$line"
        done
    fi
    
    # Show quota metrics if available
    local quota_metric_count=$(($(wc -l < "$QUOTA_SUMMARY_FILE") - 1))
    if [[ $quota_metric_count -gt 0 ]]; then
        echo ""
        printf "  ${BLUE}Quota Metrics Available:${NC}\n"
        print_success_item "$quota_metric_count quota metrics fetched"
        
        # Show source region quota summary
        local source_quota=$(awk -F',' '$1 == "'$SOURCE_REGION'" {print $0}' "$QUOTA_SUMMARY_FILE" | tail -1)
        if [[ -n "$source_quota" ]]; then
            echo ""
            printf "  ${BLUE}Source Region Quota Sample:${NC}\n"
            echo "$source_quota" | awk -F',' '{printf "    Metric: %s\n    Limit: %s\n    Usage: %s%%\n", $3, $4, $7}' | while read -r line; do
                printf "    %s\n" "$line"
            done
        fi
    else
        echo ""
        print_warning_item "No quota metrics available (quota API may not be enabled)"
    fi
    
    # Show resources that will need quota in target region
    local target_quota_resources=$(jq '.data | 
        map(select(.type | startswith("microsoft.compute") or startswith("microsoft.network") or startswith("microsoft.storage"))) | 
        length' "$INVENTORY_FILE" 2>/dev/null || echo "0")
    
    if [[ $target_quota_resources -gt 0 ]]; then
        echo ""
        print_kv "Resources Needing Quota (Target)" "$target_quota_resources" "${YELLOW}"
        print_info_item "These resources will require quota allocation in $TARGET_REGION"
    fi
    
    print_box_end
}

# ==============================================================================
# Display complete execution summary
# ==============================================================================
display_complete_summary() {
    echo ""
    
    # Display all summaries
    display_inventory_summary
    echo ""
    
    display_pricing_summary
    echo ""
    
    display_quota_summary
    echo ""
    
    display_availability_summary
    echo ""
    
    display_comparative_summary_shell
    echo ""
    
    display_execution_stats
    echo ""
    
    # Display output files
    print_box "OUTPUT FILES GENERATED"
    
    printf "  ${GREEN}✓${NC} output/source_inventory.json\n"
    printf "  ${GREEN}✓${NC} output/source_inventory_summary.csv\n"
    printf "  ${GREEN}✓${NC} output/price_lookup.csv\n"
    printf "  ${GREEN}✓${NC} output/quota_source_region.json\n"
    printf "  ${GREEN}✓${NC} output/quota_target_region.json\n"
    printf "  ${GREEN}✓${NC} output/quota_summary.csv\n"
    printf "  ${GREEN}✓${NC} output/target_region_availability.json\n"
    printf "  ${GREEN}✓${NC} output/service_availability_comparison.csv\n"
    printf "  ${GREEN}✓${NC} output/service_availability_comparison.json\n"
    printf "  ${GREEN}✓${NC} output/availability_summary.txt\n"
    printf "  ${GREEN}✓${NC} output/unique_tuples.json\n"
    printf "  ${GREEN}✓${NC} output/run.log\n"
    
    print_box_end
    
    # Final status
    if [[ $ERROR_COUNT -eq 0 ]]; then
        printf "\n%s" "${GREEN}"
        printf "╔════════════════════════════════════════════════════════════════════════════╗\n"
        printf "║                                                                            ║\n"
        printf "║  ✅ EXECUTION COMPLETED SUCCESSFULLY                                        ║\n"
        printf "║                                                                            ║\n"
        printf "╚════════════════════════════════════════════════════════════════════════════╝\n"
        printf "%s\n" "${NC}"
    else
        printf "\n%s" "${YELLOW}"
        printf "╔════════════════════════════════════════════════════════════════════════════╗\n"
        printf "║                                                                            ║\n"
        printf "║  ⚠️  EXECUTION COMPLETED WITH WARNINGS/ERRORS                              ║\n"
        printf "║                                                                            ║\n"
        printf "╚════════════════════════════════════════════════════════════════════════════╝\n"
        printf "%s\n" "${NC}"
    fi
}

# ==============================================================================
# Export functions for use in subshells
# ==============================================================================
export -f print_box
export -f print_box_end
export -f print_divider
export -f print_kv
export -f print_warning_item
export -f print_success_item
export -f print_error_item
export -f print_info_item
export -f display_inventory_summary
export -f display_pricing_summary
export -f display_quota_summary
export -f display_availability_summary
export -f display_comparative_summary_shell
export -f display_execution_stats
export -f display_complete_summary
