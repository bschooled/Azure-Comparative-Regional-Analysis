#!/usr/bin/env bash
# ==============================================================================
# Test Suite: Generalized SKU Provider Fetching
# ==============================================================================
# Validates the generalized fetch_provider_skus function across diverse
# Azure resource types

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Suppress color output for test logs
export NO_COLOR=1

# Source required libraries
source "${PROJECT_ROOT}/lib/utils_log.sh"
source "${PROJECT_ROOT}/lib/utils_cache.sh"
source "${PROJECT_ROOT}/lib/sku_provider.sh"

# Test configuration
CACHE_DIR="${PROJECT_ROOT}/.cache"
LOG_FILE="${PROJECT_ROOT}/tests/test.log"
TEST_RESULTS_FILE="${PROJECT_ROOT}/tests/test_results.json"

# Initialize test tracking
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS="[]"

# ==============================================================================
# Test Framework Functions
# ==============================================================================

test_start() {
    local test_name="$1"
    ((TESTS_RUN++))
    log_info "TEST [$TESTS_RUN] Starting: $test_name"
}

test_pass() {
    local test_name="$1"
    local message="${2:-Test passed}"
    ((TESTS_PASSED++))
    log_success "✓ PASS: $message"
    
    TEST_RESULTS=$(echo "$TEST_RESULTS" | jq -c \
        --arg name "$test_name" \
        --arg msg "$message" \
        '. += [{"test": $name, "status": "PASS", "message": $msg}]')
}

test_fail() {
    local test_name="$1"
    local message="${2:-Test failed}"
    ((TESTS_FAILED++))
    log_error "✗ FAIL: $message"
    
    TEST_RESULTS=$(echo "$TEST_RESULTS" | jq -c \
        --arg name "$test_name" \
        --arg msg "$message" \
        '. += [{"test": $name, "status": "FAIL", "message": $msg}]')
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"
    
    if [[ "$expected" == "$actual" ]]; then
        echo "true"
    else
        echo "false"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        log_error "  Message:  $message"
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Assertion failed}"
    
    if [[ "$condition" == "true" || "$condition" == "0" ]]; then
        echo "true"
    else
        echo "false"
        log_error "  Condition was false: $message"
    fi
}

# ==============================================================================
# Test Suite: Provider SKU Fetching
# ==============================================================================

test_fetch_compute_skus() {
    test_start "Fetch Microsoft.Compute SKUs"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.Compute" "2021-03-01")
    
    if [[ -f "$cache_file" ]] && [[ $(jq '. | length' "$cache_file" 2>/dev/null || echo 0) -gt 0 ]]; then
        test_pass "Fetch Microsoft.Compute SKUs" "Successfully fetched $(jq '. | length' "$cache_file") compute SKUs"
    else
        test_fail "Fetch Microsoft.Compute SKUs" "No compute SKUs found or cache file invalid"
    fi
}

test_fetch_storage_skus() {
    test_start "Fetch Microsoft.Storage SKUs"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.Storage" "2021-06-01")
    
    if [[ -f "$cache_file" ]] && [[ $(jq '. | length' "$cache_file" 2>/dev/null || echo 0) -gt 0 ]]; then
        test_pass "Fetch Microsoft.Storage SKUs" "Successfully fetched $(jq '. | length' "$cache_file") storage SKUs"
    else
        test_fail "Fetch Microsoft.Storage SKUs" "No storage SKUs found or cache file invalid"
    fi
}

test_fetch_postgresql_skus() {
    test_start "Fetch Microsoft.DBforPostgreSQL SKUs"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.DBforPostgreSQL" "2021-06-01")
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            test_pass "Fetch Microsoft.DBforPostgreSQL SKUs" "Successfully fetched $count PostgreSQL SKUs"
        else
            # Empty result is OK - some providers might not support the /skus endpoint
            test_pass "Fetch Microsoft.DBforPostgreSQL SKUs" "Query completed (empty result - provider may not support /skus endpoint)"
        fi
    else
        test_fail "Fetch Microsoft.DBforPostgreSQL SKUs" "Cache file not created"
    fi
}

test_fetch_mysql_skus() {
    test_start "Fetch Microsoft.DBforMySQL SKUs"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.DBforMySQL" "2021-06-01")
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            test_pass "Fetch Microsoft.DBforMySQL SKUs" "Successfully fetched $count MySQL SKUs"
        else
            test_pass "Fetch Microsoft.DBforMySQL SKUs" "Query completed (empty result - provider may not support /skus endpoint)"
        fi
    else
        test_fail "Fetch Microsoft.DBforMySQL SKUs" "Cache file not created"
    fi
}

test_fetch_cosmosdb_skus() {
    test_start "Fetch Microsoft.DocumentDB SKUs (Cosmos)"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.DocumentDB" "2021-11-15")
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            test_pass "Fetch Microsoft.DocumentDB SKUs" "Successfully fetched $count Cosmos SKUs"
        else
            test_pass "Fetch Microsoft.DocumentDB SKUs" "Query completed (empty result - provider may not support /skus endpoint)"
        fi
    else
        test_fail "Fetch Microsoft.DocumentDB SKUs" "Cache file not created"
    fi
}

test_fetch_cache_skus() {
    test_start "Fetch Microsoft.Cache SKUs (Redis)"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.Cache" "2021-06-01")
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            test_pass "Fetch Microsoft.Cache SKUs" "Successfully fetched $count cache SKUs"
        else
            test_pass "Fetch Microsoft.Cache SKUs" "Query completed (empty result - provider may not support /skus endpoint)"
        fi
    else
        test_fail "Fetch Microsoft.Cache SKUs" "Cache file not created"
    fi
}

test_fetch_web_skus() {
    test_start "Fetch Microsoft.Web SKUs (App Service)"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.Web" "2021-02-01")
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            test_pass "Fetch Microsoft.Web SKUs" "Successfully fetched $count web SKUs"
        else
            test_pass "Fetch Microsoft.Web SKUs" "Query completed (empty result - provider may not support /skus endpoint)"
        fi
    else
        test_fail "Fetch Microsoft.Web SKUs" "Cache file not created"
    fi
}

test_fetch_sql_skus() {
    test_start "Fetch Microsoft.Sql SKUs"
    
    local cache_file
    cache_file=$(fetch_provider_skus "Microsoft.Sql" "2021-05-01-preview")
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        if [[ $count -gt 0 ]]; then
            test_pass "Fetch Microsoft.Sql SKUs" "Successfully fetched $count SQL SKUs"
        else
            test_pass "Fetch Microsoft.Sql SKUs" "Query completed (empty result - provider may not support /skus endpoint)"
        fi
    else
        test_fail "Fetch Microsoft.Sql SKUs" "Cache file not created"
    fi
}

# ==============================================================================
# Test Suite: Caching and Performance
# ==============================================================================

test_cache_hit() {
    test_start "Cache hit on second fetch"
    
    # First call will fetch
    local cache_file1
    cache_file1=$(fetch_provider_skus "Microsoft.Compute" "2021-03-01")
    
    # Record initial cache hit count
    local hits_before=$(grep -c "Using cached" "${LOG_FILE}" 2>/dev/null || echo 0)
    
    # Second call should hit cache
    local cache_file2
    cache_file2=$(fetch_provider_skus "Microsoft.Compute" "2021-03-01")
    
    local hits_after=$(grep -c "Using cached" "${LOG_FILE}" 2>/dev/null || echo 0)
    
    if [[ $hits_after -gt $hits_before ]]; then
        test_pass "Cache hit on second fetch" "Cache was successfully reused"
    else
        test_fail "Cache hit on second fetch" "Cache was not reused"
    fi
}

test_cache_files_created() {
    test_start "Cache files created with correct naming"
    
    # Trigger fetches for multiple providers
    fetch_provider_skus "Microsoft.Compute" "2021-03-01" > /dev/null 2>&1
    fetch_provider_skus "Microsoft.Storage" "2021-06-01" > /dev/null 2>&1
    
    local compute_cache="${CACHE_DIR}/skus_microsoftcompute.json"
    local storage_cache="${CACHE_DIR}/skus_microsoftstorage.json"
    
    local compute_exists="false"
    local storage_exists="false"
    
    [[ -f "$compute_cache" ]] && compute_exists="true"
    [[ -f "$storage_cache" ]] && storage_exists="true"
    
    if [[ "$compute_exists" == "true" ]] && [[ "$storage_exists" == "true" ]]; then
        test_pass "Cache files created with correct naming" "Both cache files exist with normalized names"
    else
        test_fail "Cache files created with correct naming" "Missing cache files: compute=$compute_exists, storage=$storage_exists"
    fi
}

# ==============================================================================
# Test Suite: SKU Availability Checking
# ==============================================================================

test_check_standard_vm_available() {
    test_start "Check Standard_B2ms VM availability in eastus"
    
    if check_provider_sku_available "Microsoft.Compute" "Standard_B2ms" "eastus" 2>/dev/null; then
        test_pass "Check Standard_B2ms VM availability" "Standard_B2ms is available in eastus"
    else
        test_fail "Check Standard_B2ms VM availability" "Standard_B2ms not found or unavailable in eastus"
    fi
}

test_check_storage_available() {
    test_start "Check Standard_LRS storage availability in eastus"
    
    if check_provider_sku_available "Microsoft.Storage" "Standard_LRS" "eastus" 2>/dev/null; then
        test_pass "Check Standard_LRS storage availability" "Standard_LRS is available in eastus"
    else
        test_fail "Check Standard_LRS storage availability" "Standard_LRS not found or unavailable in eastus"
    fi
}

test_check_unavailable_sku() {
    test_start "Check unavailable SKU returns false"
    
    # Try to find a very unlikely SKU name
    if ! check_provider_sku_available "Microsoft.Compute" "NonExistent_SKU_12345" "eastus" 2>/dev/null; then
        test_pass "Check unavailable SKU" "Correctly returned false for non-existent SKU"
    else
        test_fail "Check unavailable SKU" "Should have returned false for non-existent SKU"
    fi
}

# ==============================================================================
# Test Suite: SKU Information Retrieval
# ==============================================================================

test_get_sku_info() {
    test_start "Retrieve detailed SKU information"
    
    local sku_info
    sku_info=$(get_provider_sku_info "Microsoft.Storage" "Standard_LRS" 2>/dev/null)
    
    if [[ -n "$sku_info" ]] && echo "$sku_info" | jq -e '.name' > /dev/null 2>&1; then
        local sku_name=$(echo "$sku_info" | jq -r '.name')
        test_pass "Retrieve detailed SKU information" "Retrieved info for SKU: $sku_name"
    else
        test_fail "Retrieve detailed SKU information" "Could not retrieve SKU information"
    fi
}

test_list_skus() {
    test_start "List all SKUs for a provider"
    
    local sku_list
    sku_list=$(list_provider_skus "Microsoft.Compute" 2>/dev/null)
    
    local sku_count=$(echo "$sku_list" | wc -l | tr -d ' ')
    
    if [[ $sku_count -gt 0 ]]; then
        test_pass "List all SKUs for a provider" "Found $sku_count unique compute SKUs"
    else
        test_fail "List all SKUs for a provider" "No SKUs found for Microsoft.Compute"
    fi
}

test_list_locations() {
    test_start "List available locations for a provider"
    
    local location_list
    location_list=$(list_provider_locations "Microsoft.Compute" 2>/dev/null)
    
    local location_count=$(echo "$location_list" | wc -l | tr -d ' ')
    
    if [[ $location_count -gt 0 ]]; then
        # Check if eastus is in the list
        if echo "$location_list" | grep -q "eastus"; then
            test_pass "List available locations" "Found $location_count locations for Microsoft.Compute (includes eastus)"
        else
            test_pass "List available locations" "Found $location_count locations for Microsoft.Compute"
        fi
    else
        test_fail "List available locations" "No locations found for Microsoft.Compute"
    fi
}

# ==============================================================================
# Test Suite: Error Handling
# ==============================================================================

test_missing_provider_parameter() {
    test_start "Handle missing provider parameter"
    
    if ! fetch_provider_skus "" 2>/dev/null; then
        test_pass "Handle missing provider parameter" "Correctly rejected empty provider name"
    else
        test_fail "Handle missing provider parameter" "Should have rejected empty provider name"
    fi
}

test_invalid_region_handling() {
    test_start "Handle region-specific fetch with invalid region"
    
    local cache_file
    cache_file=$(fetch_provider_region_skus "Microsoft.Compute" "invalid-region-xyz" 2>/dev/null)
    
    if [[ -f "$cache_file" ]]; then
        local count=$(jq '. | length' "$cache_file" 2>/dev/null || echo 0)
        # Should return empty array for invalid region
        if [[ $count -eq 0 ]]; then
            test_pass "Handle region-specific fetch" "Correctly returned empty array for invalid region"
        else
            test_fail "Handle region-specific fetch" "Should have returned empty array, got $count results"
        fi
    else
        test_fail "Handle region-specific fetch" "Cache file not created"
    fi
}

# ==============================================================================
# Main Test Execution
# ==============================================================================

main() {
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  Generalized SKU Provider Fetching - Test Suite                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Ensure cache directory exists
    mkdir -p "$CACHE_DIR"
    
    # Run all tests
    test_fetch_compute_skus
    test_fetch_storage_skus
    test_fetch_postgresql_skus
    test_fetch_mysql_skus
    test_fetch_cosmosdb_skus
    test_fetch_cache_skus
    test_fetch_web_skus
    test_fetch_sql_skus
    
    test_cache_hit
    test_cache_files_created
    
    test_check_standard_vm_available
    test_check_storage_available
    test_check_unavailable_sku
    
    test_get_sku_info
    test_list_skus
    test_list_locations
    
    test_missing_provider_parameter
    test_invalid_region_handling
    
    # Print summary
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  TEST SUMMARY                                                  ║"
    echo "╠════════════════════════════════════════════════════════════════╣"
    echo "║  Total Tests:    $TESTS_RUN"
    echo "║  Passed:         $TESTS_PASSED"
    echo "║  Failed:         $TESTS_FAILED"
    echo "║  Success Rate:   $(awk "BEGIN {printf \"%.1f\", ($TESTS_PASSED/$TESTS_RUN)*100}")%"
    echo "╚════════════════════════════════════════════════════════════════╝"
    
    # Save results to JSON
    echo "$TEST_RESULTS" | jq '.' > "$TEST_RESULTS_FILE"
    echo ""
    echo "Detailed results saved to: $TEST_RESULTS_FILE"
    
    # Return appropriate exit code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return 0
    else
        return 1
    fi
}

main "$@"
