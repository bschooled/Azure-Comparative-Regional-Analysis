#!/bin/bash
################################################################################
# Script: services_compare.sh
# Purpose: Full service comparison between two Azure regions
# Usage: ./services_compare.sh --source-region <region> --target-region <region>
#
# Features:
#   - Enumerate all Azure services in both regions
#   - Fetch SKU information for major service categories
#   - Generate comparative analysis
#   - Output to CSV, JSON, and shell display
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source libraries
source lib/utils_log.sh
source lib/utils_cache.sh
source lib/display.sh
source lib/service_comparison.sh

################################################################################
# CONFIGURATION
################################################################################

SOURCE_REGION=""
TARGET_REGION=""
OUTPUT_DIR=""
OUTPUT_FORMATS="csv,json,display"
CACHE_DIR="${CACHE_DIR:-.cache}"
VERBOSE=false

# Export variables needed by sourced functions
export CACHE_DIR

# Set log file after cache dir is established
LOG_FILE="${CACHE_DIR}/services_compare.log"

# Ensure log and cache directories exist before logging
mkdir -p "$CACHE_DIR"
mkdir -p "$(dirname "$LOG_FILE")"

################################################################################
# FUNCTIONS
################################################################################

# Display usage information
usage() {
    cat << 'EOF'
Usage: ./services_compare.sh --source-region <region> --target-region <region> [OPTIONS]

Required Arguments:
  --source-region <region>    Source region (e.g., eastus)
  --target-region <region>    Target region for comparison (e.g., westeurope)

Optional Arguments:
  --output-dir <path>         Output directory (default: current directory)
  --output-formats <csv,json> Output formats: csv, json, display (default: all)
  --cache-dir <path>          Cache directory for API responses (default: .cache)
  --verbose                   Enable verbose logging
  --help                       Display this help message

Examples:
  # Basic comparison
  ./services_compare.sh --source-region eastus --target-region westeurope

  # With custom output directory
  ./services_compare.sh --source-region eastus --target-region westeurope --output-dir ./reports

  # JSON output only
  ./services_compare.sh --source-region eastus --target-region westeurope --output-formats json

EOF
    exit "${1:-0}"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --source-region)
                SOURCE_REGION="$2"
                shift 2
                ;;
            --target-region)
                TARGET_REGION="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --output-formats)
                OUTPUT_FORMATS="$2"
                shift 2
                ;;
            --cache-dir)
                CACHE_DIR="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                usage 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage 1
                ;;
        esac
    done
}

# Validate inputs
validate_inputs() {
    if [[ -z "$SOURCE_REGION" ]]; then
        log_error "Missing required argument: --source-region"
        usage 1
    fi
    
    if [[ -z "$TARGET_REGION" ]]; then
        log_error "Missing required argument: --target-region"
        usage 1
    fi
    
    # Set default output directory if not specified
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="./output"
    fi
    
    # Verify regions exist
    if ! az account list-locations --query "[?name=='$SOURCE_REGION']" --output tsv &>/dev/null; then
        log_error "Invalid source region: $SOURCE_REGION"
        return 1
    fi
    
    if ! az account list-locations --query "[?name=='$TARGET_REGION']" --output tsv &>/dev/null; then
        log_error "Invalid target region: $TARGET_REGION"
        return 1
    fi
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Setup cache
    export CACHE_DIR
    init_cache "$CACHE_DIR" || {
        log_error "Failed to initialize cache"
        return 1
    }
}

# Display summary
display_summary() {
    local csv_file="$1"
    local json_file="$2"
    
    echo ""
    display_header "SERVICE COMPARISON SUMMARY"
    echo "Source Region: $SOURCE_REGION"
    echo "Target Region: $TARGET_REGION"
    echo ""
    
    if [[ -f "$json_file" ]]; then
        echo "Top 20 providers by SKU gaps (prioritizing Compute):"
        echo "─────────────────────────────────────────────────────────────────"
        
                jq -r '
                    def setdiff(a; b): [a[] as $x | select((b | index($x)) | not)];
                        def skuKeys(skus): (skus // [] | map((.name // "") + "|" + (.resourceType // "")) | unique);
                        map(
                                (skuKeys(.sourceRegion.skus)) as $src
                                | (skuKeys(.targetRegion.skus)) as $tgt
                                | (setdiff($src; $tgt)) as $onlySrc
                                | (setdiff($tgt; $src)) as $onlyTgt
                                | {
                                        provider,
                                        status,
                                        sourceSkuCount: ($src | length),
                                        targetSkuCount: ($tgt | length),
                                        onlyInSource: ($onlySrc | length),
                                        onlyInTarget: ($onlyTgt | length),
                                        totalGap: (($onlySrc | length) + ($onlyTgt | length))
                                    }
                        ) as $rows
            | (
                ($rows | map(select(.provider == "Microsoft.Compute"))[0])
                // ($rows | map(select(.provider | startswith("Microsoft.Compute")))[0])
              ) as $compute
                        | ($rows | map(select(.provider != ($compute.provider // ""))) | map(select(.totalGap > 0)) | sort_by(-.totalGap, .provider)) as $rest
            | ([ $compute ] + $rest)
            | map(select(.provider != null))
            | .[:20]
            | ("Provider\tGap\tOnlySrc\tOnlyTgt\tSrcSKUs\tTgtSKUs\tStatus"),
              (.[] | [
                (.provider | sub("^Microsoft\\."; "")),
                (.totalGap | tostring),
                (.onlyInSource | tostring),
                (.onlyInTarget | tostring),
                (.sourceSkuCount | tostring),
                (.targetSkuCount | tostring),
                (.status // "")
              ] | @tsv)
        ' "$json_file" | column -t -s $'\t'

        echo ""
        echo "Provider status summary:"
        jq -r '
            group_by(.status)[]
            | {status: (.[0].status // "UNKNOWN"), count: length}
            | "  \(.status): \(.count)"
        ' "$json_file" | sort
        echo ""
        return 0
    fi

    if [[ -f "$csv_file" ]]; then
        echo "Comparison Results (CSV preview):"
        echo "─────────────────────────────────────────────────────────────────"
        tail -n +2 "$csv_file" | head -20
        echo ""
    fi
}

# Main execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log_info "Starting service comparison: $SOURCE_REGION -> $TARGET_REGION"
    
    # Generate outputs with region names in filenames
    local json_file="$OUTPUT_DIR/${SOURCE_REGION}_vs_${TARGET_REGION}_providers.json"
    local csv_file="$OUTPUT_DIR/${SOURCE_REGION}_vs_${TARGET_REGION}_providers.csv"
    
    log_info "Generating comparison outputs (JSON + CSV)..."
    generate_comparison_outputs "$SOURCE_REGION" "$TARGET_REGION" "$csv_file" "$json_file"
    
    # Display summary if requested
    if [[ "$OUTPUT_FORMATS" == *"display"* ]]; then
        display_summary "$csv_file" "$json_file"
    fi
    
    # Show execution time
    local end_time
    end_time=$(date +%s)
    local elapsed=$((end_time - start_time))
    
    log_info "Service comparison completed in ${elapsed}s"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Output files: ${SOURCE_REGION}_vs_${TARGET_REGION}_providers.{json,csv}"
}

################################################################################
# ENTRY POINT
################################################################################

# Parse arguments
parse_args "$@"

# Validate inputs
validate_inputs || exit 1

# Execute main logic
main || exit 1

log_info "Service comparison completed successfully"
