#!/usr/bin/env bash
# ==============================================================================
# Comprehensive SKU Query Engine
# ==============================================================================
# This library provides high-level functions to query SKUs across all Azure
# service categories using the service catalog and generic SKU provider.
#
# Features:
#   - Query SKUs by service category (compute, storage, ai, etc.)
#   - Aggregate SKUs across multiple providers
#   - Regional filtering and availability checking
#   - Structured output for comparison tools
# ==============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/service_catalog.sh"
source "${SCRIPT_DIR}/sku_provider.sh"
source "${SCRIPT_DIR}/utils_log.sh"
source "${SCRIPT_DIR}/utils_cache.sh"

# ==============================================================================
# Query SKUs for a specific service category
#
# This function:
#   1. Looks up providers for the category from service catalog
#   2. Fetches SKUs from each provider using generic SKU provider
#   3. Aggregates results with provider metadata
#   4. Caches results for performance
#
# Usage:
#   query_category_skus "compute" "eastus"
#   query_category_skus "ai" "swedencentral"
#   query_category_skus "databases" "" # All regions
#
# Output: JSON array with SKUs enriched with provider and category metadata
# ==============================================================================
query_category_skus() {
    local category="$1"
    local region="${2:-}"  # Optional region filter
    
    if [[ -z "$category" ]]; then
        log_error "query_category_skus: category required"
        return 1
    fi
    
    log_info "Querying SKUs for category: $category${region:+ in region: $region}"
    
    # Get providers for this category
    local providers
    providers=$(get_service_providers "$category") || {
        log_error "Invalid category: $category"
        return 1
    }
    
    # Create aggregated results file
    local result_file="/tmp/category_skus_${category}_${region:-all}_$$.json"
    echo "[]" > "$result_file"
    
    local total_skus=0
    
    # Query each provider
    for provider in $providers; do
        log_info "  Fetching SKUs from provider: $provider"
        
        # Get API version for this provider
        local api_version
        api_version=$(get_provider_api_version "$provider")
        
        # Fetch SKUs using generic provider
        local sku_file
        if [[ -n "$region" ]]; then
            sku_file=$(fetch_provider_region_skus "$provider" "$region" "$api_version")
        else
            sku_file=$(fetch_provider_skus "$provider" "$api_version")
        fi
        
        if [[ ! -f "$sku_file" ]]; then
            log_warning "    No SKUs retrieved for $provider"
            continue
        fi
        
        # Count SKUs
        local provider_sku_count
        provider_sku_count=$(jq '. | length' "$sku_file" 2>/dev/null || echo 0)
        
        if [[ "$provider_sku_count" -eq 0 ]]; then
            log_warning "    No SKUs found for $provider"
            continue
        fi
        
        log_success "    Retrieved $provider_sku_count SKUs from $provider"
        ((total_skus += provider_sku_count))
        
        # Enrich SKUs with metadata and append to results
        local enriched_file="/tmp/enriched_skus_$$.json"
        jq --arg provider "$provider" --arg category "$category" \
            'map(. + {provider: $provider, category: $category})' \
            "$sku_file" > "$enriched_file"
        
        # Merge into result
        jq -s '.[0] + .[1]' "$result_file" "$enriched_file" > "/tmp/merged_$$.json"
        mv "/tmp/merged_$$.json" "$result_file"
        rm -f "$enriched_file"
    done
    
    log_success "Total SKUs retrieved for $category: $total_skus"
    
    # Output result file path
    echo "$result_file"
    return 0
}

# ==============================================================================
# Query SKUs across multiple categories
#
# Usage:
#   query_multi_category_skus "compute storage networking" "eastus"
#   query_multi_category_skus "ai databases analytics" "swedencentral"
#
# Output: JSON array with SKUs from all specified categories
# ==============================================================================
query_multi_category_skus() {
    local categories="$1"
    local region="${2:-}"
    
    if [[ -z "$categories" ]]; then
        log_error "query_multi_category_skus: categories required"
        return 1
    fi
    
    log_info "Querying multiple categories: $categories${region:+ in region: $region}"
    
    local result_file="/tmp/multi_category_skus_$$.json"
    echo "[]" > "$result_file"
    
    local total_skus=0
    
    for category in $categories; do
        local category_file
        category_file=$(query_category_skus "$category" "$region") || {
            log_warning "Failed to query category: $category"
            continue
        }
        
        local category_count
        category_count=$(jq '. | length' "$category_file" 2>/dev/null || echo 0)
        ((total_skus += category_count))
        
        # Merge results
        jq -s '.[0] + .[1]' "$result_file" "$category_file" > "/tmp/merged_$$.json"
        mv "/tmp/merged_$$.json" "$result_file"
        rm -f "$category_file"
    done
    
    log_success "Total SKUs retrieved across all categories: $total_skus"
    
    echo "$result_file"
    return 0
}

# ==============================================================================
# Query ALL available SKUs across all service categories
#
# Usage:
#   query_all_skus "eastus"
#   query_all_skus "" # All regions
#
# Output: JSON array with SKUs from all categories
# ==============================================================================
query_all_skus() {
    local region="${1:-}"
    
    log_info "Querying ALL service categories${region:+ in region: $region}"
    
    # Get all categories
    local all_categories
    all_categories=$(list_service_categories | tr '\n' ' ')
    
    query_multi_category_skus "$all_categories" "$region"
}

# ==============================================================================
# Compare SKUs between two regions for a category
#
# Usage:
#   compare_category_skus_between_regions "compute" "eastus" "swedencentral"
#   compare_category_skus_between_regions "ai" "westus2" "norwayeast"
#
# Output: JSON object with comparison results
# ==============================================================================
compare_category_skus_between_regions() {
    local category="$1"
    local source_region="$2"
    local target_region="$3"
    
    if [[ -z "$category" || -z "$source_region" || -z "$target_region" ]]; then
        log_error "compare_category_skus_between_regions: category, source_region, and target_region required"
        return 1
    fi
    
    log_info "Comparing $category SKUs: $source_region → $target_region"
    
    # Query source region
    local source_file
    source_file=$(query_category_skus "$category" "$source_region") || {
        log_error "Failed to query source region: $source_region"
        return 1
    }
    
    # Query target region
    local target_file
    target_file=$(query_category_skus "$category" "$target_region") || {
        log_error "Failed to query target region: $target_region"
        return 1
    }
    
    # Perform comparison
    local result_file="/tmp/sku_comparison_$$.json"
    
    jq -n \
        --arg category "$category" \
        --arg source "$source_region" \
        --arg target "$target_region" \
        --slurpfile source_skus "$source_file" \
        --slurpfile target_skus "$target_file" \
        '{
            category: $category,
            source_region: $source,
            target_region: $target,
            source_skus: $source_skus[0],
            target_skus: $target_skus[0],
            source_count: ($source_skus[0] | length),
            target_count: ($target_skus[0] | length),
            source_only: ($source_skus[0] | map(.name) - ($target_skus[0] | map(.name))),
            target_only: ($target_skus[0] | map(.name) - ($source_skus[0] | map(.name))),
            common: (($source_skus[0] | map(.name)) as $s | ($target_skus[0] | map(.name)) as $t | $s - ($s - $t))
        }' > "$result_file"
    
    # Cleanup temp files
    rm -f "$source_file" "$target_file"
    
    log_success "Comparison complete"
    
    echo "$result_file"
    return 0
}

# ==============================================================================
# Generate SKU availability report for a category
#
# Usage:
#   generate_category_report "compute" "eastus" "swedencentral"
#   generate_category_report "databases" "westus2" "norwayeast"
#
# Output: Human-readable report to stdout
# ==============================================================================
generate_category_report() {
    local category="$1"
    local source_region="$2"
    local target_region="$3"
    
    local comparison_file
    comparison_file=$(compare_category_skus_between_regions "$category" "$source_region" "$target_region") || {
        log_error "Failed to generate comparison"
        return 1
    }
    
    local category_name
    category_name=$(get_category_display_name "$category")
    
    echo "=================================================="
    echo "SKU Availability Report"
    echo "Category: $category_name"
    echo "Source Region: $source_region"
    echo "Target Region: $target_region"
    echo "=================================================="
    echo ""
    
    local source_count=$(jq -r '.source_count' "$comparison_file")
    local target_count=$(jq -r '.target_count' "$comparison_file")
    local common_count=$(jq -r '.common | length' "$comparison_file")
    local source_only_count=$(jq -r '.source_only | length' "$comparison_file")
    local target_only_count=$(jq -r '.target_only | length' "$comparison_file")
    
    echo "Summary:"
    echo "  Source SKUs: $source_count"
    echo "  Target SKUs: $target_count"
    echo "  Common SKUs: $common_count"
    echo "  Source Only: $source_only_count"
    echo "  Target Only: $target_only_count"
    echo ""
    
    if [[ $source_only_count -gt 0 ]]; then
        echo "SKUs NOT available in target region:"
        jq -r '.source_only[]' "$comparison_file" | sed 's/^/  - /'
        echo ""
    fi
    
    if [[ $target_only_count -gt 0 ]]; then
        echo "SKUs ONLY available in target region:"
        jq -r '.target_only[]' "$comparison_file" | sed 's/^/  - /'
        echo ""
    fi
    
    rm -f "$comparison_file"
    
    return 0
}

# ==============================================================================
# List all SKUs for a category in a specific region
#
# Usage:
#   list_category_skus "compute" "eastus"
#   list_category_skus "ai" "swedencentral" | grep -i "gpt"
#
# Output: List of SKU names (one per line)
# ==============================================================================
list_category_skus() {
    local category="$1"
    local region="${2:-}"
    
    local sku_file
    sku_file=$(query_category_skus "$category" "$region") || return 1
    
    jq -r '.[] | .name' "$sku_file" 2>/dev/null | sort -u
    
    rm -f "$sku_file"
    
    return 0
}

# ==============================================================================
# Check if a specific SKU is available in a region for a category
#
# Usage:
#   check_category_sku_availability "compute" "Standard_B2ms" "swedencentral"
#   check_category_sku_availability "ai" "S0" "eastus"
#
# Returns: 0 if available, 1 if not available
# ==============================================================================
check_category_sku_availability() {
    local category="$1"
    local sku_name="$2"
    local region="$3"
    
    if [[ -z "$category" || -z "$sku_name" || -z "$region" ]]; then
        log_error "check_category_sku_availability: category, sku_name, and region required"
        return 1
    fi
    
    # Get providers for category
    local providers
    providers=$(get_service_providers "$category") || return 1
    
    # Check each provider
    for provider in $providers; do
        if check_provider_sku_available "$provider" "$sku_name" "$region"; then
            log_info "SKU '$sku_name' is available in $region via $provider"
            return 0
        fi
    done
    
    log_info "SKU '$sku_name' is NOT available in $region for category $category"
    return 1
}

# Export all functions
export -f query_category_skus
export -f query_multi_category_skus
export -f query_all_skus
export -f compare_category_skus_between_regions
export -f generate_category_report
export -f list_category_skus
export -f check_category_sku_availability
