#!/usr/bin/env bash
# ==============================================================================
# Azure Comparative Regional Analysis - Main Entry Point
# ==============================================================================
# Purpose: Inventory Azure resources in a source region, map to pricing meters,
#          and check availability in a target region
# Author: Generated for Principal Solutions Engineer
# ==============================================================================

set -uo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
OUTPUT_DIR="${SCRIPT_DIR}/output"
CACHE_DIR="${SCRIPT_DIR}/.cache"
LOG_FILE="${OUTPUT_DIR}/run.log"

# Export for subshells
export SCRIPT_DIR LIB_DIR OUTPUT_DIR CACHE_DIR LOG_FILE

# Source library modules (order matters!)
source "${LIB_DIR}/utils_log.sh"
source "${LIB_DIR}/utils_cache.sh"
source "${LIB_DIR}/utils_http.sh"
source "${LIB_DIR}/region_mapping.sh"
source "${LIB_DIR}/service_comparison.sh"  # Shared caching and SKU query functions
source "${LIB_DIR}/sku_provider.sh"
source "${LIB_DIR}/args.sh"
source "${LIB_DIR}/inventory.sh"
source "${LIB_DIR}/pricing.sh"
source "${LIB_DIR}/availability.sh"
source "${LIB_DIR}/quota.sh"
source "${LIB_DIR}/data_processing.sh"
source "${LIB_DIR}/comparative_analysis.sh"
source "${LIB_DIR}/inventory_comparison.sh"  # Inventory-specific comparison output
source "${LIB_DIR}/display.sh"

# ==============================================================================
# Main execution
# ==============================================================================
main() {
    # Initialize
    mkdir -p "${OUTPUT_DIR}" "${CACHE_DIR}"
    init_logging
    
    log_info "Azure Comparative Regional Analysis started"
    log_info "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    
    # Parse and validate arguments
    parse_arguments "$@"
    validate_arguments
    
    # Verify prerequisites
    verify_prerequisites
    verify_azure_login
    
    # Display configuration
    display_config
    
    # ---- Phase 1: Resource Inventory via Azure Resource Graph ----
    log_info "=== Phase 1: Resource Inventory ==="
    local start_time=$(date +%s)
    
    # If a pre-generated inventory file is provided, ingest it; otherwise run ARG query
    if [[ -n "$INVENTORY_INPUT_FILE" ]]; then
        ingest_inventory_file || exit 1
    else
        run_resource_graph_query
    fi
    
    local end_time=$(date +%s)
    log_info "Phase 1 completed in $((end_time - start_time)) seconds"
    
    # ---- Phase 2: Summarize Inventory ----
    log_info "=== Phase 2: Inventory Summarization ==="
    start_time=$(date +%s)
    
    summarize_inventory
    derive_unique_tuples
    
    end_time=$(date +%s)
    log_info "Phase 2 completed in $((end_time - start_time)) seconds"
    
    # ---- Phase 3: Pricing Meter Enrichment ----
    log_info "=== Phase 3: Pricing Meter Enrichment ==="
    start_time=$(date +%s)
    
    fetch_pricing_data
    
    end_time=$(date +%s)
    log_info "Phase 3 completed in $((end_time - start_time)) seconds"
    
    # ---- Phase 4: Target Region Availability ----
    log_info "=== Phase 4: Target Region Availability Check ==="
    start_time=$(date +%s)
    
    check_target_availability
    
    end_time=$(date +%s)
    log_info "Phase 4 completed in $((end_time - start_time)) seconds"
    
    # ---- Phase 5: Service Quota Analysis ----
    log_info "=== Phase 5: Service Quota Analysis ==="
    start_time=$(date +%s)
    
    fetch_source_region_quotas
    fetch_target_region_quotas
    generate_quota_summary
    enrich_tuples_with_quota
    
    end_time=$(date +%s)
    log_info "Phase 5 completed in $((end_time - start_time)) seconds"
    
    # ---- Phase 6: Comparative Analysis ----
    log_info "=== Phase 6: Comparative Regional Analysis ==="
    start_time=$(date +%s)
    
    generate_comparative_tables
    generate_availability_summary
    
    end_time=$(date +%s)
    log_info "Phase 6 completed in $((end_time - start_time)) seconds"
    
    # ---- Phase 7: Generate Standard Comparison Outputs ----
    log_info "=== Phase 7: Generate Standard Comparison Outputs ==="
    start_time=$(date +%s)
    
    local json_file="${OUTPUT_DIR}/inventory_${SOURCE_REGION}_vs_${TARGET_REGION}_providers.json"
    local csv_file="${OUTPUT_DIR}/inventory_${SOURCE_REGION}_vs_${TARGET_REGION}_providers.csv"
    
    generate_inventory_comparison_outputs "$SOURCE_REGION" "$TARGET_REGION" "$csv_file" "$json_file"
    
    end_time=$(date +%s)
    log_info "Phase 7 completed in $((end_time - start_time)) seconds"
    
    # ---- Summary and Exit ----
    log_info "=== Execution Complete ==="
    display_summary
    display_comparative_summary
    
    # Display shell summary
    display_complete_summary
    
    # Exit with appropriate code
    determine_exit_code
}

# Run main
main "$@"
