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
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$PROJECT_ROOT"

# Source libraries
source lib/utils_log.sh
source lib/utils_cache.sh
source lib/display.sh
source lib/region_mapping.sh
source lib/python_cli.sh
source lib/service_comparison.sh

################################################################################
# CONFIGURATION
################################################################################

SOURCE_REGION=""
TARGET_REGION=""
OUTPUT_DIR=""
OUTPUT_FORMATS="csv,json,display"
CACHE_DIR="${CACHE_DIR:-.cache}"
PARALLEL="${PARALLEL:-4}"
PROVIDER_SCOPE="deployable"
VERBOSE=false

# Export variables needed by sourced functions
export CACHE_DIR
export PARALLEL
export PROVIDER_SCOPE

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
    --parallel <n>              Provider comparison concurrency (default: 4)
    --all                       Compare every provider namespace visible in ARM
    --verbose                   Enable verbose logging and cache trace lines
  --help                       Display this help message

Environment Variables:
    CACHE_DIR                   Cache directory (same as --cache-dir)
    CACHE_TRACE=1               Print per-provider SKU cache hit/miss lines
    DEBUG=1                     Enable debug logging (written to services_compare.log)

Examples:
  # Basic comparison
  ./services_compare.sh --source-region eastus --target-region westeurope

  # With custom output directory
  ./services_compare.sh --source-region eastus --target-region westeurope --output-dir ./reports

  # JSON output only
  ./services_compare.sh --source-region eastus --target-region westeurope --output-formats json

    # Custom provider comparison concurrency
    ./services_compare.sh --source-region eastus --target-region centralus --parallel 12

    # Force full ARM provider enumeration
    ./services_compare.sh --source-region eastus --target-region centralus --all

    # Azure Government
    az cloud set --name AzureUSGovernment
    az login
    ./services_compare.sh --source-region usgovvirginia --target-region usgovtexas

    # Show cache usage (SKU cache hit/miss lines)
    ./services_compare.sh --source-region eastus --target-region westeurope --verbose

Notes:
    - Default mode compares deployable service providers from the repo catalog, not every ARM platform namespace.
    - Use --all to restore the full provider enumeration behavior.
    - ARM API calls follow the active Azure CLI cloud metadata.
    - Pricing enrichment is not used by this script.

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
            --parallel)
                PARALLEL="$2"
                export PARALLEL
                shift 2
                ;;
            --all)
                PROVIDER_SCOPE="all"
                export PROVIDER_SCOPE
                shift
                ;;
            --verbose)
                VERBOSE=true
                export DEBUG=1
                export CACHE_TRACE=1
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
    # Fail early with actionable messages if dependencies are missing.
    verify_prerequisites
    verify_azure_login

    if [[ -z "$SOURCE_REGION" ]]; then
        log_error "Missing required argument: --source-region"
        usage 1
    fi
    
    if [[ -z "$TARGET_REGION" ]]; then
        log_error "Missing required argument: --target-region"
        usage 1
    fi

    if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -lt 1 ]]; then
        log_error "Invalid --parallel value: must be a positive integer"
        usage 1
    fi
    
    # Set default output directory if not specified
    if [[ -z "$OUTPUT_DIR" ]]; then
        OUTPUT_DIR="./output"
    fi
    
    # Verify regions exist
    SOURCE_REGION="$(resolve_region "$SOURCE_REGION")" || return 1
    TARGET_REGION="$(resolve_region "$TARGET_REGION")" || return 1
    validate_cloud_region_alignment "$SOURCE_REGION" "$TARGET_REGION" || return 1
    
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

    if render_provider_comparison_report "$json_file"; then
        return 0
    fi
    
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
    log_info "Provider comparison concurrency: $PARALLEL"
    log_info "Provider scope: $PROVIDER_SCOPE"
    
    # Generate outputs with region names in filenames
    local json_file="$OUTPUT_DIR/${SOURCE_REGION}_vs_${TARGET_REGION}_providers.json"
    local csv_file="$OUTPUT_DIR/${SOURCE_REGION}_vs_${TARGET_REGION}_providers.csv"
    
    log_info "Generating comparison outputs (JSON + CSV)..."
    generate_comparison_outputs "$SOURCE_REGION" "$TARGET_REGION" "$csv_file" "$json_file" "$PROVIDER_SCOPE"
    
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

# Always show cache usage so it's obvious whether cache is working.
display_execution_summary

log_info "Service comparison completed successfully"
