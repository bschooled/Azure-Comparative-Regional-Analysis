# E2E Test Framework - Quota Testing Integration

## Overview

The e2e test framework has been enhanced with comprehensive quota analysis testing. The framework now validates all aspects of quota functionality including data processing, display formatting, and end-to-end integration.

## Test Suite Structure

### 1. **Quota Analysis Tests** (`tests/test_quota_analysis.sh`)
Dedicated test file for quota-specific functionality.

**Tests Included:**
- CSV parsing with quoted fields (9 tests total)
- Top 5 quota consumers extraction
- Quota display formatting with proper alignment
- Resources needing quota calculation logic
- Empty quota file handling
- Field count validation (7 required fields)
- Region filtering (source vs target)
- Percentage calculation accuracy

**Run Command:**
```bash
bash tests/test_quota_analysis.sh
```

**Expected Output:**
```
================================================================================
Quota Analysis Test Suite
================================================================================
[✓] CSV parsing correctly identified 6 centralus records
[✓] Top 5 extraction returned 5 metrics
[✓] Top 5 correctly sorted by percentage (first=34%)
[✓] Quota display formatting correct
[✓] Resources needing quota correctly shows 0 (all fit in target)
[✓] Empty quota file handled correctly (0 records)
[✓] Quota CSV has correct field count (7 fields)
[✓] Region filtering works correctly (centralus=6, eastus=2)
[✓] Percentage calculation correct (120/350 = 34%)

================================================================================
Quota Test Results
================================================================================
Passed: 9
Failed: 0
```

### 2. **End-to-End Tests** (`tests/e2e_test.sh`)
Enhanced with 5 new quota-specific tests integrated into the existing test suite.

**New Quota Tests (Tests 9-13):**
- Test 9: Quota summary file structure and headers
- Test 10: Quota data structure validation
- Test 11: Quota display output format verification
- Test 12: Execution statistics display order
- Test 13: Quota resource count logic validation

**Run Command:**
```bash
bash tests/e2e_test.sh
```

**Test Coverage:**
- Total: 13 tests (8 existing + 5 new quota tests)
- All tests validate with test inventory and real SKU lookups
- Tests verify output files, formatting, and data integrity

### 3. **Comprehensive Test Runner** (`tests/run_all_tests.sh`)
Master test orchestrator that runs all test suites and generates unified report.

**Runs:**
1. Quota Analysis Tests
2. End-to-End Tests
3. Quick Validation Tests

**Run Command:**
```bash
bash tests/run_all_tests.sh
```

**Output Includes:**
- Individual test suite results
- Summary with pass/fail counts
- Pass rate percentage
- Test coverage details
- Generated reports in `test_e2e/all_tests/`

## Quota Testing Coverage

### Display Format Tests
- ✅ Execution statistics appear first in output
- ✅ Top 5 quota consumers extracted and formatted correctly
- ✅ Proper alignment and spacing in terminal display
- ✅ Resources needing quota shows 0 when all fit in target

### Data Processing Tests
- ✅ CSV parsing handles quoted field values correctly
- ✅ Region filtering (centralus, eastus, etc.) works
- ✅ Percentage calculations are accurate (usage/limit*100)
- ✅ Empty quota data handled gracefully

### Validation Tests
- ✅ CSV structure requires 7 fields exactly
- ✅ Quota file headers present and correct
- ✅ Field count validation (6 commas between 7 fields)
- ✅ Sorting by usage percentage (highest first)

### Integration Tests
- ✅ E2E tests validate quota section in output display
- ✅ Quota display appears in correct section order
- ✅ Status messages display appropriately
- ✅ Quota files generated with correct structure

## Test Data

### Sample Quota CSV Format
```csv
region,resourceType,quotaMetric,limit,currentUsage,availableQuota,percentUsed
"centralus","microsoft.compute/virtualmachines","Standard DS Family vCPUs",350,120,230,34
"centralus","microsoft.compute/virtualmachines","Standard BS Family vCPUs",100,24,76,24
"eastus","microsoft.compute/virtualmachines","Standard DS Family vCPUs",350,0,350,0
```

### Top 5 Display Format
```
Top 5 Quota Consumers in Source Region:
  Standard DS Family vCPUs                       120 / 350   34% used
  Standard Instances                              85 / 250   34% used
  Standard FSv2 Family vCPUs                      15 / 50    30% used
  Standard BS Family vCPUs                        24 / 100   24% used
  Premium Storage Account Disks                  120 / 1000  12% used
```

## Test Artifacts

### Test Output Files
```
test_e2e/
├── quota_tests/
│   ├── test_quota.csv                    # Test data
│   ├── empty_quota.csv                   # Edge case
│   └── report.txt                        # Quota test report
├── all_tests/
│   ├── quota_test.log                    # Detailed quota test log
│   ├── e2e_test.log                      # E2E test log
│   ├── quick_validation.log              # Quick validation log
│   └── COMPLETE_TEST_REPORT.txt          # Unified test report
├── e2e_run.log                           # E2E execution log
└── report.txt                            # E2E summary report
```

## How to Use

### Run Individual Test Suite
```bash
# Quota tests only
bash tests/test_quota_analysis.sh

# E2E tests only
bash tests/e2e_test.sh

# Quick validation only
bash tests/quick_validation.sh
```

### Run All Tests
```bash
bash tests/run_all_tests.sh
```

### Run Specific E2E Test
Individual tests within e2e_test.sh can be executed (see `tests/e2e_test.sh` for test function names).

### View Test Reports
```bash
cat test_e2e/all_tests/COMPLETE_TEST_REPORT.txt
cat test_e2e/quota_tests/report.txt
cat test_e2e/report.txt
```

## Quota Analysis Scope Notes

The quota analysis is available in specific scopes:

| Scope | Quota Support | Notes |
|-------|---------------|-------|
| `--all` | ❌ No | Tenant-wide queries don't support quota APIs |
| `--subscriptions <csv>` | ✅ Yes | Per-subscription quotas available |
| `--rg <subId:rgName>` | ✅ Yes | Resource group quotas available |
| `--inventory-file <path>` | ⚠️ No | No API calls, depends on source file |

### To Enable Quota Testing with Real Data
```bash
# Use with subscription scope
./inv.sh --subscriptions "your-subscription-id" \
         --source-region centralus \
         --target-region eastus \
         --all

# Or resource group scope
./inv.sh --rg "subscription-id:resource-group-name" \
         --source-region centralus \
         --target-region eastus
```

## Test Validations

### CSV Parsing
- Correctly parses CSV with quoted string fields
- Handles metric names with spaces (e.g., "Standard DS Family vCPUs")
- Extracts numeric fields (limit, usage, available)
- Filters by region accurately

### Display Formatting
- Metric names left-aligned with 45 character width
- Usage/limit right-aligned with space padding
- Percentage values right-aligned
- Top 5 sorted by usage percentage descending
- Proper spacing and alignment for terminal readability

### Logic Validation
- Resources needing quota shows 0 when source ≤ target available
- Resources needing quota shows count when source > target available
- Empty quota data displays appropriate "no metrics" message
- All execution statistics shown first in output

## Next Steps

To extend quota testing:
1. Add region-specific tests (multiple source/target combinations)
2. Add quota trend tests (usage over time)
3. Add quota alert tests (threshold validation)
4. Add resource-type-specific quota tests
5. Add quota comparison between regions

## References

- [Quota Display Improvements](../QUOTA_DISPLAY_IMPROVEMENTS.md)
- [Test E2E Guide](../tests/E2E_TEST_GUIDE.md)
- [Main Script](../inv.sh)
- [Display Library](../lib/display.sh)
- [Quota Library](../lib/quota.sh)
