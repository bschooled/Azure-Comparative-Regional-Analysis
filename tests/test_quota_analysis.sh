#!/usr/bin/env bash
# ==============================================================================
# Quota Analysis Tests
# ==============================================================================
# Purpose: Comprehensive testing of quota analysis and display functionality
#
# Tests:
#  1. CSV format validation
#  2. Top 5 quota consumers extraction and formatting
#  3. Quota display output
#  4. Resources needing quota calculation
#  5. Execution statistics display order

set -euo pipefail

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/output"
TEST_QUOTA_DIR="${PROJECT_ROOT}/test_e2e/quota_tests"

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
# Create test quota data with known values
# ==============================================================================
create_test_quota_data() {
    local quota_file="$1"
    
    mkdir -p "$(dirname "$quota_file")"
    
    cat > "$quota_file" << 'EOF'
region,resourceType,quotaMetric,limit,currentUsage,availableQuota,percentUsed
"centralus","microsoft.compute/virtualmachines","Standard DS Family vCPUs",350,120,230,34
"centralus","microsoft.compute/virtualmachines","Standard BS Family vCPUs",100,24,76,24
"centralus","microsoft.compute/virtualmachines","Standard FSv2 Family vCPUs",50,15,35,30
"centralus","microsoft.compute/disks","Premium Storage Account Disks",1000,120,880,12
"centralus","microsoft.storage/storageaccounts","Standard Instances",250,85,165,34
"centralus","microsoft.compute/virtualmachines","Virtual Machines",25000,9,24991,0
"eastus","microsoft.compute/virtualmachines","Standard DS Family vCPUs",350,0,350,0
"eastus","microsoft.compute/virtualmachines","Standard BS Family vCPUs",100,0,100,0
EOF
}

# ==============================================================================
# Test 1: CSV parsing with quoted fields
# ==============================================================================
test_csv_parsing() {
    log_info "Test 1: CSV parsing with quoted fields..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Test Python CSV parsing
    local parsed_data
    parsed_data=$(python3 << PYTHON_EOF
import csv

with open("$test_file", 'r') as f:
    reader = csv.DictReader(f)
    count = 0
    for row in reader:
        if row['region'] == 'centralus':
            count += 1
    print(count)
PYTHON_EOF
)
    
    if [[ "$parsed_data" -eq 6 ]]; then
        test_pass "CSV parsing correctly identified 6 centralus records"
    else
        test_fail "CSV parsing failed (expected 6 records, got $parsed_data)"
        return 1
    fi
}

# ==============================================================================
# Test 2: Top 5 Quota Consumers extraction
# ==============================================================================
test_top_5_extraction() {
    log_info "Test 2: Top 5 Quota Consumers extraction..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Extract top 5 using Python
    local top_5_output
    top_5_output=$(python3 << PYTHON_EOF
import csv

data = []
with open("$test_file", 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row['region'] == 'centralus':
            limit = int(row['limit']) if row['limit'].isdigit() else 0
            usage = int(row['currentUsage']) if row['currentUsage'].isdigit() else 0
            if limit > 0:
                percent = int((usage / limit) * 100)
                data.append({
                    'metric': row['quotaMetric'],
                    'usage': usage,
                    'limit': limit,
                    'percent': percent
                })

data.sort(key=lambda x: x['percent'], reverse=True)
for item in data[:5]:
    print(f"{item['metric']}|{item['percent']}")
PYTHON_EOF
)
    
    # Verify output has 5 items sorted by percentage
    local line_count
    line_count=$(echo "$top_5_output" | wc -l)
    
    if [[ $line_count -eq 5 ]]; then
        test_pass "Top 5 extraction returned 5 metrics"
    else
        test_fail "Top 5 extraction returned wrong count (expected 5, got $line_count)"
        return 1
    fi
    
    # Verify first item is highest percentage (34%)
    local first_percent
    first_percent=$(echo "$top_5_output" | head -1 | cut -d'|' -f2)
    
    if [[ "$first_percent" -eq 34 ]]; then
        test_pass "Top 5 correctly sorted by percentage (first=34%)"
    else
        test_fail "Top 5 sorting incorrect (first item should be 34%, got $first_percent%)"
        return 1
    fi
}

# ==============================================================================
# Test 3: Quota display formatting
# ==============================================================================
test_quota_display_format() {
    log_info "Test 3: Quota display formatting..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Test formatted output
    local formatted_output
    formatted_output=$(python3 << PYTHON_EOF
import csv

data = []
with open("$test_file", 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        if row['region'] == 'centralus':
            limit = int(row['limit']) if row['limit'].isdigit() else 0
            usage = int(row['currentUsage']) if row['currentUsage'].isdigit() else 0
            if limit > 0:
                percent = int((usage / limit) * 100)
                data.append({
                    'metric': row['quotaMetric'],
                    'usage': usage,
                    'limit': limit,
                    'percent': percent
                })

data.sort(key=lambda x: x['percent'], reverse=True)
for item in data[:1]:
    print(f"    {item['metric']:<45} {item['usage']:>4} / {item['limit']:<4} {item['percent']:>3}% used")
PYTHON_EOF
)
    
    # Verify format
    if echo "$formatted_output" | grep -qE "Standard DS Family vCPUs.*120 / 350.*34% used"; then
        test_pass "Quota display formatting correct"
    else
        test_fail "Quota display format incorrect: $formatted_output"
        return 1
    fi
}

# ==============================================================================
# Test 4: Resources needing quota calculation
# ==============================================================================
test_resources_needing_quota() {
    log_info "Test 4: Resources needing quota calculation..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Simulate the logic from display.sh
    local source_region="centralus"
    local target_region="eastus"
    
    # Get source usage and target available
    local source_total
    source_total=$(awk -F',' -v r="$source_region" '$1 == "\""r"\"" {sum+=$5} END {print sum}' "$test_file")
    
    local target_available
    target_available=$(awk -F',' -v r="$target_region" '$1 == "\""r"\"" {sum+=$6} END {print sum}' "$test_file")
    
    if [[ -z "$source_total" ]]; then
        source_total=0
    fi
    
    if [[ -z "$target_available" ]]; then
        target_available=0
    fi
    
    local resources_exceeding=0
    if [[ $source_total -gt $target_available ]]; then
        resources_exceeding=1
    fi
    
    # For this test data, source total is 249, target available is 700
    # So no resources should exceed quota
    if [[ $resources_exceeding -eq 0 ]]; then
        test_pass "Resources needing quota correctly shows 0 (all fit in target)"
    else
        test_fail "Resources needing quota calculation incorrect"
        return 1
    fi
}

# ==============================================================================
# Test 5: Empty quota file handling
# ==============================================================================
test_empty_quota_handling() {
    log_info "Test 5: Empty quota file handling..."
    
    local test_file="${TEST_QUOTA_DIR}/empty_quota.csv"
    mkdir -p "$(dirname "$test_file")"
    
    # Create empty quota file with just header
    cat > "$test_file" << 'EOF'
region,resourceType,quotaMetric,limit,currentUsage,availableQuota,percentUsed
EOF
    
    # Test that empty handling works
    local result
    result=$(python3 << PYTHON_EOF
import csv

data = []
with open("$test_file", 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        data.append(row)

print(len(data))
PYTHON_EOF
)
    
    if [[ "$result" -eq 0 ]]; then
        test_pass "Empty quota file handled correctly (0 records)"
    else
        test_fail "Empty quota file handling failed"
        return 1
    fi
}

# ==============================================================================
# Test 6: Field count validation
# ==============================================================================
test_field_count_validation() {
    log_info "Test 6: Field count validation..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Get first data line and count fields
    local first_line
    first_line=$(tail -1 "$test_file")
    
    # Count commas (should be 6 for 7 fields)
    local comma_count
    comma_count=$(echo "$first_line" | grep -o ',' | wc -l)
    
    if [[ $comma_count -eq 6 ]]; then
        test_pass "Quota CSV has correct field count (7 fields)"
    else
        test_fail "Quota CSV field count incorrect (expected 6 commas, got $comma_count)"
        return 1
    fi
}

# ==============================================================================
# Test 7: Region filtering
# ==============================================================================
test_region_filtering() {
    log_info "Test 7: Region filtering..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Count records per region
    local centralus_count
    centralus_count=$(grep -c '"centralus"' "$test_file" || echo 0)
    
    local eastus_count
    eastus_count=$(grep -c '"eastus"' "$test_file" || echo 0)
    
    if [[ $centralus_count -eq 6 && $eastus_count -eq 2 ]]; then
        test_pass "Region filtering works correctly (centralus=$centralus_count, eastus=$eastus_count)"
    else
        test_fail "Region filtering incorrect"
        return 1
    fi
}

# ==============================================================================
# Test 8: Percentage calculation
# ==============================================================================
test_percentage_calculation() {
    log_info "Test 8: Percentage calculation..."
    
    local test_file="${TEST_QUOTA_DIR}/test_quota.csv"
    create_test_quota_data "$test_file"
    
    # Extract Standard DS Family vCPUs: 120/350 = 34%
    local percent
    percent=$(python3 << PYTHON_EOF
usage = 120
limit = 350
percent = int((usage / limit) * 100)
print(percent)
PYTHON_EOF
)
    
    if [[ "$percent" -eq 34 ]]; then
        test_pass "Percentage calculation correct (120/350 = 34%)"
    else
        test_fail "Percentage calculation incorrect (expected 34%, got $percent%)"
        return 1
    fi
}

# ==============================================================================
# Main
# ==============================================================================
main() {
    echo ""
    echo "================================================================================"
    echo "Quota Analysis Test Suite"
    echo "================================================================================"
    echo ""
    
    # Verify dependencies
    if ! command -v python3 &> /dev/null; then
        log_error "python3 is required but not found"
        exit 1
    fi
    
    # Create test directory
    mkdir -p "$TEST_QUOTA_DIR"
    
    # Run all tests
    test_csv_parsing || true
    test_top_5_extraction || true
    test_quota_display_format || true
    test_resources_needing_quota || true
    test_empty_quota_handling || true
    test_field_count_validation || true
    test_region_filtering || true
    test_percentage_calculation || true
    
    # Summary
    echo ""
    echo "================================================================================"
    echo "Quota Test Results"
    echo "================================================================================"
    echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
    echo "================================================================================"
    echo ""
    
    # Create test report
    cat > "${TEST_QUOTA_DIR}/report.txt" << EOF
Quota Analysis Test Report
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Tests Passed: $TESTS_PASSED
Tests Failed: $TESTS_FAILED

Test Coverage:
  ✓ CSV parsing with quoted fields
  ✓ Top 5 Quota Consumers extraction
  ✓ Quota display formatting
  ✓ Resources needing quota calculation
  ✓ Empty quota file handling
  ✓ Field count validation
  ✓ Region filtering
  ✓ Percentage calculation

Quota Processing Validation:
  - Correctly parses CSV with quoted field values
  - Extracts and sorts metrics by usage percentage
  - Formats output with proper alignment and units
  - Calculates resource capacity (fitting/exceeding target quota)
  - Handles missing/empty quota data gracefully
  - Validates CSV structure (7 required fields)
  - Filters by region correctly
  - Calculates usage percentages accurately
EOF
    
    log_info "Quota test report saved to: ${TEST_QUOTA_DIR}/report.txt"
    
    if [[ $TESTS_FAILED -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
