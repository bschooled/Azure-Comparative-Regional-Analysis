#!/usr/bin/env bash
# ==============================================================================
# SKU Query CLI - Command-line interface for comprehensive SKU queries
# ==============================================================================
# This script provides a user-friendly command-line interface to query Azure
# SKUs across all service categories.
#
# Usage:
#   ./lib/sku_query.sh list-categories
#   ./lib/sku_query.sh query compute eastus
#   ./lib/sku_query.sh compare compute eastus swedencentral
#   ./lib/sku_query.sh report ai westus2 norwayeast
#   ./lib/sku_query.sh check compute Standard_B2ms swedencentral
# ==============================================================================

set -euo pipefail

# Script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Initialize environment variables
export LOG_FILE="${LOG_FILE:-.cache/sku_query.log}"
export CACHE_DIR="${CACHE_DIR:-.cache}"
export LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

# Source libraries
source "${ROOT_DIR}/lib/utils_log.sh"
source "${ROOT_DIR}/lib/utils_cache.sh"
source "${ROOT_DIR}/lib/sku_query_engine.sh"

# ==============================================================================
# Display usage information
# ==============================================================================
show_usage() {
    cat <<EOF
SKU Query Tool - Comprehensive Azure SKU Querying

Usage:
    $(basename "$0") <command> [options]

Commands:
    list-categories
        List all available service categories

    list-providers <category>
        List providers for a specific category

    query <category> [region]
        Query SKUs for a category (optionally filtered by region)

    compare <category> <source-region> <target-region>
        Compare SKUs between two regions for a category

    report <category> <source-region> <target-region>
        Generate detailed availability report

    check <category> <sku-name> <region>
        Check if a specific SKU is available

    list <category> [region]
        List all SKU names for a category

    query-all [region]
        Query SKUs across all categories

    catalog
        Display the complete service catalog

Examples:
    # List all service categories
    $(basename "$0") list-categories

    # Query compute SKUs in East US
    $(basename "$0") query compute eastus

    # Compare AI service SKUs between regions
    $(basename "$0") compare ai westus2 norwayeast

    # Generate detailed report
    $(basename "$0") report databases eastus swedencentral

    # Check if a specific VM SKU is available
    $(basename "$0") check compute Standard_D4s_v5 swedencentral

    # List all AI SKUs in a region
    $(basename "$0") list ai westus2

    # Query all SKUs across all services
    $(basename "$0") query-all eastus

Service Categories:
    compute        Virtual Machines, VM Scale Sets
    storage        Blob, Files, Disks
    networking     Load Balancers, Firewall, VPN
    databases      SQL, PostgreSQL, MySQL, CosmosDB
    analytics      Synapse, Data Factory, Kusto
    ai             Cognitive Services, OpenAI, ML
    containers     AKS, Container Registry, ACI
    serverless     Functions, App Service, Container Apps
    monitoring     Log Analytics, Application Insights
    integration    Service Bus, Event Hub, Event Grid

EOF
}

# ==============================================================================
# Command handlers
# ==============================================================================

cmd_list_categories() {
    echo "Available Service Categories:"
    echo "=============================="
    echo ""
    
    for category in $(list_service_categories); do
        local display_name=$(get_category_display_name "$category")
        printf "  %-15s %s\n" "$category" "$display_name"
    done
}

cmd_list_providers() {
    local category="$1"
    
    if [[ -z "$category" ]]; then
        log_error "Category required"
        echo "Usage: $(basename "$0") list-providers <category>"
        return 1
    fi
    
    local providers
    providers=$(get_service_providers "$category") || {
        log_error "Invalid category: $category"
        return 1
    }
    
    echo "Providers for category: $category"
    echo "================================="
    echo ""
    
    for provider in $providers; do
        local api_version=$(get_provider_api_version "$provider")
        local resource_types=$(get_provider_resource_types "$provider")
        
        echo "Provider: $provider"
        echo "  API Version: $api_version"
        echo "  Resource Types: $resource_types"
        echo ""
    done
}

cmd_query() {
    local category="$1"
    local region="${2:-}"
    
    if [[ -z "$category" ]]; then
        log_error "Category required"
        echo "Usage: $(basename "$0") query <category> [region]"
        return 1
    fi
    
    local result_file
    result_file=$(query_category_skus "$category" "$region") || {
        log_error "Query failed"
        return 1
    }
    
    # Output results as JSON
    cat "$result_file"
    
    rm -f "$result_file"
}

cmd_compare() {
    local category="$1"
    local source_region="$2"
    local target_region="$3"
    
    if [[ -z "$category" || -z "$source_region" || -z "$target_region" ]]; then
        log_error "Category, source region, and target region required"
        echo "Usage: $(basename "$0") compare <category> <source-region> <target-region>"
        return 1
    fi
    
    local result_file
    result_file=$(compare_category_skus_between_regions "$category" "$source_region" "$target_region") || {
        log_error "Comparison failed"
        return 1
    }
    
    # Output results as JSON
    cat "$result_file"
    
    rm -f "$result_file"
}

cmd_report() {
    local category="$1"
    local source_region="$2"
    local target_region="$3"
    
    if [[ -z "$category" || -z "$source_region" || -z "$target_region" ]]; then
        log_error "Category, source region, and target region required"
        echo "Usage: $(basename "$0") report <category> <source-region> <target-region>"
        return 1
    fi
    
    generate_category_report "$category" "$source_region" "$target_region"
}

cmd_check() {
    local category="$1"
    local sku_name="$2"
    local region="$3"
    
    if [[ -z "$category" || -z "$sku_name" || -z "$region" ]]; then
        log_error "Category, SKU name, and region required"
        echo "Usage: $(basename "$0") check <category> <sku-name> <region>"
        return 1
    fi
    
    if check_category_sku_availability "$category" "$sku_name" "$region"; then
        echo "✓ SKU '$sku_name' is AVAILABLE in $region"
        return 0
    else
        echo "✗ SKU '$sku_name' is NOT AVAILABLE in $region"
        return 1
    fi
}

cmd_list() {
    local category="$1"
    local region="${2:-}"
    
    if [[ -z "$category" ]]; then
        log_error "Category required"
        echo "Usage: $(basename "$0") list <category> [region]"
        return 1
    fi
    
    list_category_skus "$category" "$region"
}

cmd_query_all() {
    local region="${1:-}"
    
    local result_file
    result_file=$(query_all_skus "$region") || {
        log_error "Query failed"
        return 1
    }
    
    # Output results as JSON
    cat "$result_file"
    
    rm -f "$result_file"
}

cmd_catalog() {
    print_service_catalog
}

# ==============================================================================
# Main command dispatcher
# ==============================================================================

main() {
    local command="${1:-}"
    
    if [[ -z "$command" ]]; then
        show_usage
        exit 1
    fi
    
    # Shift to get command arguments
    shift
    
    case "$command" in
        list-categories)
            cmd_list_categories "$@"
            ;;
        list-providers)
            cmd_list_providers "$@"
            ;;
        query)
            cmd_query "$@"
            ;;
        compare)
            cmd_compare "$@"
            ;;
        report)
            cmd_report "$@"
            ;;
        check)
            cmd_check "$@"
            ;;
        list)
            cmd_list "$@"
            ;;
        query-all)
            cmd_query_all "$@"
            ;;
        catalog)
            cmd_catalog "$@"
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            log_error "Unknown command: $command"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
