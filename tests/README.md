# Test Framework - Quick Start Guide

## Overview
The Azure Comparative Regional Analysis tool includes a comprehensive test framework with dedicated quota analysis testing.

## Quick Start

### Run All Tests
```bash
bash tests/run_all_tests.sh
```

This executes:
1. **Quota Analysis Tests** (9 tests) - CSV parsing, display formatting, calculations
2. **End-to-End Tests** (13 tests) - Full pipeline with 5 quota-specific tests
3. **Quick Validation** - Basic functionality checks

### Individual Test Suites

```bash
# Quota-specific tests only
bash tests/test_quota_analysis.sh

# End-to-end tests with full pipeline
bash tests/e2e_test.sh

# Quick validation checks
bash tests/quick_validation.sh
```

## Test Results

### Expected Output
```
✅ ALL TESTS PASSED (100% pass rate)
- 9 Quota Analysis Tests: PASS
- 13 End-to-End Tests: PASS (including 5 quota tests)
- Quick Validation: PASS
```

### Reports Generated
```
test_e2e/
├── all_tests/COMPLETE_TEST_REPORT.txt    # Comprehensive summary
├── quota_tests/report.txt                # Quota test details
└── report.txt                            # E2E summary
```

## What's Tested

### Quota Analysis Module
- CSV parsing with quoted fields
- Top 5 quota consumers extraction
- Display formatting and alignment
- Resources needing quota calculation
- Empty data handling
- Field validation (7 required)
- Region filtering
- Percentage calculations

### Display Format
- ✅ Execution statistics appear first
- ✅ Quota section includes top 5 consumers
- ✅ Proper formatting: `metric | usage / limit | %`
- ✅ Resources needing quota shows correct count

### End-to-End Pipeline
- Inventory generation and ingestion
- Real SKU availability checks
- Pricing lookups
- Quota analysis integration
- Display output validation

## Test Artifacts

### Test Data
- `test_e2e/quota_tests/test_quota.csv` - Sample quota data with known values
- `test_e2e/quota_tests/empty_quota.csv` - Edge case (empty data)

### Test Reports
- Full HTML/text reports in `test_e2e/all_tests/`
- Individual test logs available for debugging
- Pass/fail statistics for each test

## Running with Real Data

To test quota with actual subscription data:

```bash
# Option 1: Per-subscription quota
./inv.sh --subscriptions "your-subscription-id" \
         --source-region centralus \
         --target-region eastus \
         --all

# Option 2: Per-resource-group quota  
./inv.sh --rg "subscription-id:resource-group-name" \
         --source-region centralus \
         --target-region eastus
```

Then review quota output in the display section.

## Troubleshooting

### Tests Fail
1. Check Python3 is installed: `python3 --version`
2. Verify test files are executable: `chmod +x tests/*.sh`
3. Check Azure CLI is installed: `az --version`
4. Run with verbose output: `bash -x tests/test_quota_analysis.sh`

### Quota Data Missing
- Quota fetching requires `--subscriptions` or `--rg` scope
- `--all` scope doesn't support quota APIs
- `--inventory-file` uses pre-existing inventory only

### Display Issues
- Check `output/quota_summary.csv` exists
- Verify CSV format: 7 comma-separated fields
- Ensure quotes around string fields: `"value"`

## Files

### Test Scripts (New)
- `tests/run_all_tests.sh` - Master test orchestrator
- `tests/test_quota_analysis.sh` - Quota-specific tests

### Enhanced Scripts
- `tests/e2e_test.sh` - Added 5 quota tests (Tests 9-13)
- `lib/display.sh` - Quota display implementation
- `lib/quota.sh` - Quota analysis module

### Documentation
- `docs/QUOTA_TEST_FRAMEWORK.md` - Detailed test documentation
- `QUOTA_TEST_INTEGRATION_SUMMARY.md` - Integration summary
- `QUOTA_DISPLAY_IMPROVEMENTS.md` - Display changes

## Next Steps

1. **Run tests**: `bash tests/run_all_tests.sh`
2. **Review results**: `cat test_e2e/all_tests/COMPLETE_TEST_REPORT.txt`
3. **Check quota data**: `head -5 output/quota_summary.csv`
4. **View display output**: `grep "Top 5 Quota" output/run.log`
5. **Integration**: Add to CI/CD pipeline

## References

- [Quota Test Framework Documentation](docs/QUOTA_TEST_FRAMEWORK.md)
- [Test Integration Summary](QUOTA_TEST_INTEGRATION_SUMMARY.md)
- [Quota Display Improvements](QUOTA_DISPLAY_IMPROVEMENTS.md)

---

**Status:** ✅ 100% Test Pass Rate | **Tests:** 22+ | **Coverage:** Comprehensive
