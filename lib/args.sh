#!/usr/bin/env bash
# ==============================================================================
# Argument Parsing and Validation
# ==============================================================================

# Global variables for arguments
SOURCE_REGION=""
TARGET_REGION=""
SCOPE_TYPE=""  # all, mg, rg
MANAGEMENT_GROUP_ID=""
RESOURCE_GROUP_SPEC=""
SUBSCRIPTIONS=""
RESOURCE_TYPES=""
PARALLEL=8
CACHE_DIR="${SCRIPT_DIR}/.cache"
INVENTORY_INPUT_FILE=""

# ==============================================================================
# Parse command-line arguments
# ==============================================================================
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --source-region)
                SOURCE_REGION="$2"
                shift 2
                ;;
            --target-region)
                TARGET_REGION="$2"
                shift 2
                ;;
            --all)
                SCOPE_TYPE="all"
                shift
                ;;
            --mg)
                SCOPE_TYPE="mg"
                MANAGEMENT_GROUP_ID="$2"
                shift 2
                ;;
            --rg)
                SCOPE_TYPE="rg"
                RESOURCE_GROUP_SPEC="$2"
                shift 2
                ;;
            --subscriptions)
                SUBSCRIPTIONS="$2"
                shift 2
                ;;
            --resource-types)
                RESOURCE_TYPES="$2"
                shift 2
                ;;
            --parallel)
                PARALLEL="$2"
                shift 2
                ;;
            --cache-dir)
                CACHE_DIR="$2"
                shift 2
                ;;
            --inventory-file)
                INVENTORY_INPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "ERROR: Unknown option: $1" >&2
                echo "" >&2
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# ==============================================================================
# Validate arguments
# ==============================================================================
validate_arguments() {
    # Required arguments
    if [[ -z "$SOURCE_REGION" ]]; then
        log_error "Missing required argument: --source-region"
        exit 1
    fi
    
    if [[ -z "$TARGET_REGION" ]]; then
        log_error "Missing required argument: --target-region"
        exit 1
    fi
    
    # Resolve region names to region codes
    log_info "Resolving region names..."
    SOURCE_REGION=$(resolve_region "$SOURCE_REGION") || exit 1
    export SOURCE_REGION
    
    TARGET_REGION=$(resolve_region "$TARGET_REGION") || exit 1
    export TARGET_REGION
    
    # Scope validation (skip if ingesting a provided inventory file)
    if [[ -z "$SCOPE_TYPE" ]]; then
        if [[ -n "$INVENTORY_INPUT_FILE" ]]; then
            log_info "Skipping scope validation: using provided inventory file"
        else
            log_error "Must specify one of: --all, --mg, or --rg"
            exit 1
        fi
    fi
    
    # Additional scope-specific validation
    if [[ "$SCOPE_TYPE" == "mg" && -z "$MANAGEMENT_GROUP_ID" ]]; then
        log_error "Management group ID required with --mg"
        exit 1
    fi
    
    if [[ "$SCOPE_TYPE" == "rg" && -z "$RESOURCE_GROUP_SPEC" ]]; then
        log_error "Resource group specification required with --rg (format: subId:rgName)"
        exit 1
    fi
    
    # Validate parallel value
    if ! [[ "$PARALLEL" =~ ^[0-9]+$ ]] || [[ "$PARALLEL" -lt 1 ]]; then
        log_error "Invalid --parallel value: must be a positive integer"
        exit 1
    fi
    
    log_info "Arguments validated successfully"
}

# ==============================================================================
# Display help message
# ==============================================================================
show_help() {
    cat << EOF
Azure Comparative Regional Analysis Tool

USAGE:
    ./inv.sh --source-region <region> --target-region <region> [SCOPE] [OPTIONS]

REQUIRED ARGUMENTS:
    --source-region <region>    Source Azure region (e.g., eastus)
    --target-region <region>    Target Azure region for comparison (e.g., westeurope)

SCOPE (mutually exclusive, one required):
    --all                       Query all accessible subscriptions in tenant
    --mg <managementGroupId>    Query resources within a management group
    --rg <subId:rgName>         Query resources within a specific resource group

OPTIONS:
    --subscriptions <csv>       Comma-separated subscription IDs (overrides --all)
    --resource-types <csv>      Filter by resource types (e.g., Microsoft.Compute/virtualMachines)
    --parallel <n>              Concurrency for API calls (default: 8)
    --cache-dir <path>          Directory for caching API responses (default: ./.cache)
    --inventory-file <path>     Use a pre-generated inventory JSON (skip ARG discovery)
    -h, --help                  Show this help message

QUOTA FETCHING:
    Quota analysis is automatically enabled for per-subscription and per-resource-group scopes.
    For resource group scopes, subscription-level quota is fetched for context.
    Quota data includes both source and target region quotas when applicable.
    Gracefully skips services without available quota APIs.

OUTPUTS:
    output/source_inventory.json              - Raw ARG output
    output/source_inventory_summary.csv       - Summarized resource counts
    output/price_lookup.csv                   - Pricing meter mappings
    output/target_region_availability.json    - Availability in target region
    output/quota_source_region.json           - Service quotas in source region
    output/quota_target_region.json           - Service quotas in target region
    output/quota_summary.csv                  - Quota usage summary
    output/run.log                            - Execution log

EXAMPLES:
    # Tenant-wide scope
    ./inv.sh --all --source-region eastus --target-region westeurope

    # Management group scope
    ./inv.sh --mg Contoso-Prod --source-region eastus2 --target-region uksouth

    # Resource group scope
    ./inv.sh --rg 00000000-0000-0000-0000-000000000000:WorkloadRG \\
        --source-region westus3 --target-region centralus

    # With filtering and custom parallelism
    ./inv.sh --all --source-region eastus --target-region westeurope \\
        --resource-types "Microsoft.Compute/virtualMachines,Microsoft.Storage/storageAccounts" \\
        --parallel 12 --cache-dir /tmp/azure-cache

EOF
}

# ==============================================================================
# Display current configuration
# ==============================================================================
display_config() {
    log_info "Configuration:"
    log_info "  Source Region: $SOURCE_REGION"
    log_info "  Target Region: $TARGET_REGION"
    log_info "  Scope Type: $SCOPE_TYPE"
    
    if [[ "$SCOPE_TYPE" == "mg" ]]; then
        log_info "  Management Group: $MANAGEMENT_GROUP_ID"
    elif [[ "$SCOPE_TYPE" == "rg" ]]; then
        log_info "  Resource Group: $RESOURCE_GROUP_SPEC"
    fi
    
    if [[ -n "$SUBSCRIPTIONS" ]]; then
        log_info "  Subscriptions: $SUBSCRIPTIONS"
    fi
    
    if [[ -n "$RESOURCE_TYPES" ]]; then
        log_info "  Resource Types Filter: $RESOURCE_TYPES"
    fi
    
    log_info "  Parallel Requests: $PARALLEL"
    log_info "  Cache Directory: $CACHE_DIR"
}
