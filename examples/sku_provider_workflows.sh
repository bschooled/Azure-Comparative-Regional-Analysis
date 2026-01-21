#!/usr/bin/env bash
# ==============================================================================
# Example Workflows: Using the Generalized SKU Provider Fetching
# ==============================================================================
# This script demonstrates various ways to use the lib/sku_provider.sh
# library to query SKU availability across multiple Azure resource types

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source required libraries
export NO_COLOR=1
source "${PROJECT_ROOT}/lib/utils_log.sh"
source "${PROJECT_ROOT}/lib/utils_cache.sh"
source "${PROJECT_ROOT}/lib/sku_provider.sh"

CACHE_DIR="${PROJECT_ROOT}/.cache"
mkdir -p "$CACHE_DIR"

# ==============================================================================
# Example 1: Multi-Provider Availability Check
# ==============================================================================
example_multi_provider() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 1: Multi-Provider Availability Check                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    echo "Checking if resources are available in swedencentral across providers..."
    echo ""
    
    # Define the resources to check
    declare -a checks=(
        "Microsoft.Compute|Standard_B2ms"
        "Microsoft.Compute|Standard_D4s_v3"
        "Microsoft.Storage|Standard_LRS"
        "Microsoft.Storage|Premium_LRS"
        "Microsoft.Cache|c0"
    )
    
    for check in "${checks[@]}"; do
        IFS='|' read -r provider sku <<< "$check"
        
        if check_provider_sku_available "$provider" "$sku" "swedencentral" 2>/dev/null; then
            echo "✓ $sku ($provider) is available in swedencentral"
        else
            echo "✗ $sku ($provider) is NOT available in swedencentral"
        fi
    done
}

# ==============================================================================
# Example 2: Find Optimal Region for a Specific SKU
# ==============================================================================
example_find_region_for_sku() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 2: Find All Regions for a Specific SKU                 ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local target_sku="Standard_D2s_v3"
    local provider="Microsoft.Compute"
    
    echo "Finding all regions where $target_sku is available..."
    echo ""
    
    local locations
    locations=$(list_provider_locations "$provider" 2>/dev/null)
    
    local count=0
    local matching_regions=""
    
    for region in $locations; do
        if check_provider_sku_available "$provider" "$target_sku" "$region" 2>/dev/null; then
            matching_regions="${matching_regions}${region} "
            ((count++))
            
            # Only show first 20 to keep output manageable
            if [[ $count -le 20 ]]; then
                echo "  ✓ $region"
            fi
        fi
    done
    
    echo ""
    echo "Found in $count total regions (showing first 20)"
}

# ==============================================================================
# Example 3: Compare VM Sizes Across Regions
# ==============================================================================
example_compare_vm_sizes() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 3: Compare VM Sizes Across Regions                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local provider="Microsoft.Compute"
    declare -a regions=("eastus" "westeurope" "swedencentral" "japaneast")
    declare -a vm_sizes=("Standard_B1s" "Standard_B2ms" "Standard_D2s_v3")
    
    # Print header
    printf "%-20s" "VM Size"
    for region in "${regions[@]}"; do
        printf "%-18s" "$region"
    done
    echo ""
    echo "───────────────────────────────────────────────────────────────────────────"
    
    # Print rows
    for vm_size in "${vm_sizes[@]}"; do
        printf "%-20s" "$vm_size"
        for region in "${regions[@]}"; do
            if check_provider_sku_available "$provider" "$vm_size" "$region" 2>/dev/null; then
                printf "%-18s" "✓"
            else
                printf "%-18s" "✗"
            fi
        done
        echo ""
    done
}

# ==============================================================================
# Example 4: List Available SKUs for a Provider
# ==============================================================================
example_list_skus() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 4: List Available SKUs for a Provider                  ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local provider="Microsoft.Cache"
    echo "Listing all Cache (Redis) SKUs available in Azure..."
    echo ""
    
    local skus
    skus=$(list_provider_skus "$provider" 2>/dev/null)
    
    local count=0
    echo "$skus" | while read -r sku; do
        printf "  %s\n" "$sku"
        ((count++))
        if [[ $count -ge 15 ]]; then
            echo "  ... and $(( $(echo "$skus" | wc -l) - count )) more"
            break
        fi
    done
}

# ==============================================================================
# Example 5: Get Detailed SKU Information
# ==============================================================================
example_sku_details() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 5: Get Detailed SKU Information                        ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    local provider="Microsoft.Storage"
    local sku="Standard_LRS"
    
    echo "Getting detailed information for $sku storage SKU..."
    echo ""
    
    local info
    info=$(get_provider_sku_info "$provider" "$sku" 2>/dev/null)
    
    if [[ -n "$info" ]]; then
        echo "$info" | jq '{
            name,
            tier: .tier,
            kind: .kind,
            resourceType,
            locationCount: (.locations | length),
            locations: (.locations[0:5]),
            restrictions: (.restrictions | length)
        }' 2>/dev/null
    else
        echo "SKU information not found"
    fi
}

# ==============================================================================
# Example 6: Find Storage Accounts Available in All Regions
# ==============================================================================
example_global_availability() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 6: Find Globally Available Resources                   ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    echo "Finding storage SKUs available in ALL major regions..."
    echo ""
    
    local provider="Microsoft.Storage"
    declare -a regions=("eastus" "westeurope" "australiaeast" "japaneast" "swedencentral")
    
    local skus
    skus=$(list_provider_skus "$provider" 2>/dev/null)
    
    local global_skus=""
    local count=0
    
    echo "$skus" | while read -r sku; do
        local available_everywhere=true
        
        for region in "${regions[@]}"; do
            if ! check_provider_sku_available "$provider" "$sku" "$region" 2>/dev/null; then
                available_everywhere=false
                break
            fi
        done
        
        if [[ "$available_everywhere" == "true" ]]; then
            echo "  ✓ $sku (available in all checked regions)"
            ((count++))
            if [[ $count -ge 5 ]]; then
                break
            fi
        fi
    done
    
    echo ""
    echo "Finding SKUs available in 4+ of ${#regions[@]} major regions..."
    echo ""
    
    # This would require a more complex loop - showing concept
    echo "  (Implementation: Check each SKU against all regions, count matches)"
}

# ==============================================================================
# Example 7: Cache Statistics
# ==============================================================================
example_cache_stats() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║ Example 7: Cache Statistics                                    ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    echo "Cache files in use:"
    echo ""
    ls -lh "${CACHE_DIR}"/skus_*.json 2>/dev/null | awk '{
        size = $5
        file = $9
        gsub(/.*skus_/, "", file)
        printf "  %-40s %10s\n", file, size
    }' || echo "  (No cache files found)"
}

# ==============================================================================
# Main Execution
# ==============================================================================
main() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  SKU Provider Fetching - Example Workflows                     ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    
    example_multi_provider
    example_find_region_for_sku
    example_compare_vm_sizes
    example_list_skus
    example_sku_details
    example_cache_stats
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Examples Complete                                             ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "For more information, see: docs/SKU_PROVIDER_GUIDE.md"
}

main "$@"
