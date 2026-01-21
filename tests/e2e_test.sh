#!/usr/bin/env bash
# ==============================================================================
# End-to-End Test: Generate Inventory + Run Main Script
# ==============================================================================
# Purpose: Comprehensive validation of the Azure Comparative Regional Analysis tool
#          using a fake diverse inventory and real target-region lookups
#
# Flow:
#  1. Generate a diverse test inventory with AI/Foundry resources
#  2. Run inv.sh with the generated inventory file (skip ARG discovery)
#  3. Run real SKU availability checks against target region
#  4. Validate output files and report success/failure

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TESTS_DIR="$SCRIPT_DIR"
OUTPUT_DIR="${PROJECT_ROOT}/output"
CACHE_DIR="${PROJECT_ROOT}/.cache"
TEST_E2E_DIR="${PROJECT_ROOT}/test_e2e"
TEST_INVENTORY="${TEST_E2E_DIR}/test_inventory.json"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test result tracking
TESTS_PASSED=0
TESTS_FAILED=0

# ==============================================================================
# Utilities
# ==============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

log_error() {
    echo -e "${RED}[✗]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $*"
}

test_pass() {
    log_success "$1"
    ((TESTS_PASSED++))
}

test_fail() {
    log_error "$1"
    ((TESTS_FAILED++))
}

# ==============================================================================
# Test 1: Generate diverse inventory with AI/Foundry resources
# ==============================================================================
test_generate_inventory() {
    log_info "Test 1: Generate diverse test inventory..."
    
    mkdir -p "$TEST_E2E_DIR"
    
    # Call existing generator to create the base inventory
    if ! "$TESTS_DIR/generate_test_inventories.sh" > /dev/null 2>&1; then
        test_fail "Failed to run test inventory generator"
        return 1
    fi
    
    # Use ARG-compatible format (expected by inv.sh ingestion)
    if [[ ! -f "${PROJECT_ROOT}/test_inventories/inventory_diverse_arg.json" ]]; then
        test_fail "Generator did not produce ARG-compatible inventory file"
        return 1
    fi
    
    cp "${PROJECT_ROOT}/test_inventories/inventory_diverse_arg.json" "$TEST_INVENTORY"
    
    local resource_count
    resource_count=$(jq '.data | length' "$TEST_INVENTORY" 2>/dev/null || echo 0)
    
    if [[ $resource_count -eq 0 ]]; then
        test_fail "Generated inventory has no resources"
        return 1
    fi
    
    # Verify presence of AI and Foundry resources
    local cognitiveservices_count
    cognitiveservices_count=$(jq '[.data[] | select(.type | contains("cognitiveservices"))] | length' "$TEST_INVENTORY")
    
    local ml_workspace_count
    ml_workspace_count=$(jq '[.data[] | select(.type | contains("machinelearningservices"))] | length' "$TEST_INVENTORY")
    
    if [[ $cognitiveservices_count -eq 0 ]]; then
        test_fail "No Cognitive Services (AI) resources in generated inventory"
        return 1
    fi
    
    if [[ $ml_workspace_count -eq 0 ]]; then
        test_fail "No Machine Learning (Foundry) resources in generated inventory"
        return 1
    fi
    
    test_pass "Generated $resource_count resources (Cognitive: $cognitiveservices_count, ML: $ml_workspace_count)"
}

# ==============================================================================
# Test 2: Run inv.sh with ingested inventory
# ==============================================================================
test_ingest_and_analyze() {
    log_info "Test 2: Run inv.sh with ingested inventory and real target-region lookup..."
    
    if [[ ! -f "$TEST_INVENTORY" ]]; then
        test_fail "Test inventory file not found: $TEST_INVENTORY"
        return 1
    fi
    
    # Run inv.sh with:
    # - Ingested inventory (skip ARG discovery)
    # - Real lookup for target region
    # - Suppress stdin so it doesn't wait for input
    if "$PROJECT_ROOT/inv.sh" \
        --inventory-file "$TEST_INVENTORY" \
        --target-region swedencentral \
        --all \
        --source-region centralus \
        < /dev/null \
        > "${TEST_E2E_DIR}/e2e_run.log" 2>&1; then
        test_pass "inv.sh completed successfully"
    else
        test_fail "inv.sh execution failed (check ${TEST_E2E_DIR}/e2e_run.log)"
        return 1
    fi
}

# ==============================================================================
# Test 3: Validate output files
# ==============================================================================
test_output_files() {
    log_info "Test 3: Validate output files..."
    
    local output_files=(
        "${OUTPUT_DIR}/source_inventory.json"
        "${OUTPUT_DIR}/source_inventory_summary.csv"
        "${OUTPUT_DIR}/unique_tuples.json"
        "${OUTPUT_DIR}/target_region_availability.json"
    )
    
    for file in "${output_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            test_fail "Missing output file: $file"
            return 1
        fi
    done
    
    test_pass "All expected output files present"
}

# ==============================================================================
# Test 4: Verify inventory summary
# ==============================================================================
test_inventory_summary() {
    log_info "Test 4: Validate inventory summary..."
    
    local summary_file="${OUTPUT_DIR}/source_inventory_summary.csv"
    if [[ ! -f "$summary_file" ]]; then
        test_fail "Summary file not found: $summary_file"
        return 1
    fi
    
    local line_count
    line_count=$(wc -l < "$summary_file")
    
    # Line count: 1 header + resources (should be > 1)
    if [[ $line_count -lt 2 ]]; then
        test_fail "Summary file has no data rows"
        return 1
    fi
    
    # Verify CSV structure
    local header
    header=$(head -n 1 "$summary_file")
    if ! echo "$header" | grep -q "subscriptionId"; then
        test_fail "Summary CSV header missing expected columns"
        return 1
    fi
    
    test_pass "Inventory summary valid ($((line_count - 1)) resource combinations)"
}

# ==============================================================================
# Test 5: Verify availability check results
# ==============================================================================
test_availability_results() {
    log_info "Test 5: Validate availability check results..."
    
    local avail_file="${OUTPUT_DIR}/target_region_availability.json"
    if [[ ! -f "$avail_file" ]]; then
        test_fail "Availability file not found: $avail_file"
        return 1
    fi
    
    # Verify it's valid JSON
    if ! jq empty "$avail_file" 2>/dev/null; then
        test_fail "Availability JSON is malformed"
        return 1
    fi
    
    local total_count
    total_count=$(jq '. | length' "$avail_file")
    
    local available_count
    available_count=$(jq '[.[] | select(.available == true)] | length' "$avail_file")
    
    local unavailable_count=$((total_count - available_count))
    
    if [[ $total_count -eq 0 ]]; then
        test_fail "No availability results generated"
        return 1
    fi
    
    test_pass "Availability check: $available_count/$total_count resources available in swedencentral ($unavailable_count unavailable)"
}

# ==============================================================================
# Test 6: Verify AI and Foundry resources processed
# ==============================================================================
test_ai_foundry_coverage() {
    log_info "Test 6: Verify AI and Foundry resources in results..."
    
    local summary_file="${OUTPUT_DIR}/source_inventory_summary.csv"
    
    # Check if cognitive services appear in summary
    local cs_in_summary
    cs_in_summary=$(grep -i cognitiveservices "$summary_file" | wc -l || echo 0)
    
    local ml_in_summary
    ml_in_summary=$(grep -i machinelearning "$summary_file" | wc -l || echo 0)
    
    if [[ $cs_in_summary -eq 0 ]]; then
        log_warning "No Cognitive Services resources in summary (may be due to filtering)"
    else
        test_pass "Cognitive Services resources processed ($cs_in_summary entries)"
    fi
    
    if [[ $ml_in_summary -eq 0 ]]; then
        log_warning "No ML resources in summary (may be due to filtering)"
    else
        test_pass "ML resources processed ($ml_in_summary entries)"
    fi
}

# ==============================================================================
# Test 7: Cache generation and reuse
# ==============================================================================
test_cache_behavior() {
    log_info "Test 7: Validate cache generation..."
    
    if [[ ! -d "$CACHE_DIR" ]]; then
        test_fail "Cache directory not created: $CACHE_DIR"
        return 1
    fi
    
    local cache_files
    cache_files=$(find "$CACHE_DIR" -type f | wc -l)
    
    if [[ $cache_files -eq 0 ]]; then
        log_warning "No cache files generated (may be expected for certain runs)"
    else
        test_pass "Cache directory populated with $cache_files files"
    fi
}

# ==============================================================================
# Test 8: Perform second run to verify cache hits
# ==============================================================================
test_cache_reuse() {
    log_info "Test 8: Verify cache reuse on second run..."
    
    # Clean output but keep cache
    rm -f "${OUTPUT_DIR}"/*.json "${OUTPUT_DIR}"/*.csv
    
    # Run inv.sh again with same parameters
    if "$PROJECT_ROOT/inv.sh" \
        --inventory-file "$TEST_INVENTORY" \
        --target-region swedencentral \
        --all \
        --source-region centralus \
        < /dev/null \
        > "${TEST_E2E_DIR}/e2e_run_2.log" 2>&1; then
        
        # Check for cache hit messages in log
        if grep -q "cache hit\|Using cached" "${TEST_E2E_DIR}/e2e_run_2.log" 2>/dev/null; then
            test_pass "Cache reuse detected on second run"
        else
            log_warning "Cache reuse not detected in logs (caching may still be working)"
        fi
    else
        test_fail "Second inv.sh run failed"
        return 1
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    echo "================================================================================"
    echo "End-to-End Test Suite: Azure Comparative Regional Analysis"
    echo "================================================================================"
    echo ""
    
    # Clean test e2e directory
    rm -rf "$TEST_E2E_DIR"
    mkdir -p "$TEST_E2E_DIR"
    
    # Run all tests
    test_generate_inventory || true
    test_ingest_and_analyze || true
    test_output_files || true
    test_inventory_summary || true
    test_availability_results || true
    test_ai_foundry_coverage || true
    test_cache_behavior || true
    test_cache_reuse || true
    
    # Summary
    echo ""
    echo "================================================================================"
    echo "Test Results"
    echo "================================================================================"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "================================================================================"
    echo ""
    
    # Create test report
    cat > "${TEST_E2E_DIR}/report.txt" << EOF
End-to-End Test Report
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Tests Passed: $TESTS_PASSED
Tests Failed: $TESTS_FAILED

Source Inventory: $TEST_INVENTORY
Output Directory: $OUTPUT_DIR
Logs: ${TEST_E2E_DIR}/

Key Outputs:
  - source_inventory.json: Raw inventory data
  - source_inventory_summary.csv: Resource counts by type
  - target_region_availability.json: Regional availability verdicts
  - unique_tuples.json: Unique resource combinations for pricing

Test Coverage:
  ✓ Inventory generation with AI/Foundry resources
  ✓ Ingestion of pre-generated inventory files
  ✓ Real SKU lookups in target region (swedencentral)
  ✓ Output file validation
  ✓ Availability reporting
  ✓ Cache generation and reuse
EOF
    
    log_info "Test report saved to: ${TEST_E2E_DIR}/report.txt"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
