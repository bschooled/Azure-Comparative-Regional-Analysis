# End-to-End Test Guide

## Overview

The end-to-end test framework validates the complete workflow of the Azure Comparative Regional Analysis tool:

1. **Inventory Generation** — Creates a diverse test inventory with AI and Foundry resources
2. **Inventory Ingestion** — Skips Azure Resource Graph discovery and uses pre-generated inventory
3. **Real Region Lookups** — Performs actual SKU availability checks against the target region
4. **Output Validation** — Verifies all output files and their contents

## Running the E2E Test

```bash
cd /home/bschooley/Azure-Comparative-Regional-Analysis
./tests/e2e_test.sh
```

### Expected Output

```
================================================================================
End-to-End Test Suite: Azure Comparative Regional Analysis
================================================================================

[INFO] Test 1: Generate diverse test inventory...
[✓] Generated 33 resources (Cognitive: 3, ML: 2)
[INFO] Test 2: Run inv.sh with ingested inventory and real target-region lookup...
[✓] inv.sh completed successfully
[INFO] Test 3: Validate output files...
[✓] All expected output files present
[INFO] Test 4: Validate inventory summary...
[✓] Inventory summary valid (31 resource combinations)
[INFO] Test 5: Validate availability check results...
[✓] Availability check: 31/31 resources available in swedencentral (0 unavailable)
[INFO] Test 6: Verify AI and Foundry resources in results...
[✓] Cognitive Services resources processed (2 entries)
[✓] ML resources processed (2 entries)
[INFO] Test 7: Validate cache generation...
[✓] Cache directory populated with 15 files
[INFO] Test 8: Verify cache reuse on second run...
[✓] Cache reuse detected on second run

================================================================================
Test Results
================================================================================
Passed: 9
Failed: 0
================================================================================
```

## Test Coverage

### Test 1: Inventory Generation
- Generates diverse test inventory with 33 resources
- Includes AI services (Cognitive Services: OpenAI, Form Recognizer, Computer Vision)
- Includes Foundry services (ML Workspaces, ML Compute)
- Produces ARG-compatible JSON format

**Resources Generated:**
- 2x Virtual Machines (B2ms, D4s_v3)
- 2x Managed Disks (Standard_LRS, Premium_LRS)
- 1x Storage Account (Standard_LRS)
- 2x AKS Clusters (D2s_v3, B2ms)
- 3x PostgreSQL Flexible Servers (varied SKUs)
- 1x MySQL Flexible Server
- 1x Cosmos DB (Global, MongoDB)
- 3x Cognitive Services (OpenAI, Form Recognizer, Computer Vision) **[AI]**
- 2x ML Services (Workspace, Compute) **[Foundry]**
- 2x Azure Functions (Premium EP1, Basic B1)
- 1x App Service (S1)
- 3x Redis Cache (Basic, Standard, Premium)
- 1x SQL Server
- 1x SQL Database
- 1x Key Vault
- 1x App Insights
- 1x Event Grid Topic
- 1x Event Hub Namespace
- 1x Service Bus Namespace
- 1x Databricks Workspace
- 1x Synapse Workspace
- 1x Container App
- 1x Managed Container Environment

### Test 2: Inventory Ingestion
- Reads pre-generated inventory file
- Skips Azure Resource Graph discovery (no Azure CLI calls needed)
- Normalizes schema to ARG-compatible format
- Validates resource counts match input

**Supported Input Formats:**
1. `{ data: [...] }` — ARG-compatible format (used by e2e test)
2. `{ resources: [...], metadata: {...} }` — Generator format
3. `[ ... ]` — Raw array of resources

### Test 3: Output File Validation
- Verifies all expected output files are created:
  - `source_inventory.json` — Normalized inventory
  - `source_inventory_summary.csv` — Resource counts
  - `unique_tuples.json` — Unique combinations for pricing
  - `target_region_availability.json` — Regional availability

### Test 4: Inventory Summary
- CSV contains proper headers and data rows
- Groups resources by subscription, resource group, location, type, and SKU
- Counts instances of each combination
- For test: 31 unique resource combinations from 33 total resources

### Test 5: Availability Check Results
- Validates real SKU lookups in Sweden Central
- **Result: 31/31 resources available** (0 unavailable)
- Checks Cognitive Services availability
- Checks ML Workspace availability
- Verifies no restrictions on tested SKUs

### Test 6: AI and Foundry Coverage
- Verifies Cognitive Services appear in summary (2 entries)
- Verifies ML resources appear in summary (2 entries)
- Confirms AI and Foundry services process through full pipeline

### Test 7: Cache Generation
- Creates `.cache` directory with provider SKU files
- Generates region-specific cache files (e.g., `compute_skus_swedencentral.json`)
- Validates 15 cache files created on first run

### Test 8: Cache Reuse
- Second run detects and uses cached data
- Avoids redundant Azure API calls
- Confirms "cache hit" messages in logs
- Significantly faster execution time

## Inventory Ingestion Feature

### Command Line Usage

Run `inv.sh` with pre-generated inventory, skipping Azure Resource Graph discovery:

```bash
./inv.sh --inventory-file test_inventories/inventory_diverse_arg.json \
         --target-region swedencentral \
         --all \
         --source-region centralus
```

### Benefits

1. **No Azure Subscription Required** — Run tests without real Azure access
2. **Reproducible Testing** — Use fixed test data for consistent results
3. **Fast Validation** — Skip resource discovery, run straight to SKU checks
4. **Diverse Coverage** — Test with curated resource mix (AI, Foundry, compute, storage, etc.)

### Schema Format

The ARG-compatible format expects:

```json
{
  "data": [
    {
      "id": "unique-identifier",
      "name": "resource-name",
      "type": "Microsoft.Service/resourceType",
      "location": "region-code",
      "subscriptionId": "uuid",
      "resourceGroup": "group-name",
      "sku": "sku-name",
      "vmSize": "vm-size",
      "diskSku": "disk-sku",
      "diskSizeGB": 100,
      "storageAccountKind": "StorageV2",
      "tier": "tier-name",
      "capacity": 10,
      "properties": {}
    }
  ]
}
```

## Advanced Testing

### Custom Inventory Files

Create your own inventory for testing:

```bash
# Option 1: Use generator format
cat > my_inventory.json << 'EOF'
{
  "resources": [
    {
      "id": "VM-001",
      "type": "microsoft.compute/virtualmachines",
      "name": "my-vm",
      "vmSize": "Standard_D4s_v3",
      "location": "eastus"
    },
    {
      "id": "AI-001",
      "type": "microsoft.cognitiveservices/accounts",
      "name": "my-ai",
      "sku": "S0",
      "location": "eastus"
    }
  ]
}
EOF

# Option 2: Run inv.sh with your inventory
./inv.sh --inventory-file my_inventory.json \
         --target-region westeurope \
         --all \
         --source-region eastus
```

### Testing Different Regions

Run availability checks for different target regions:

```bash
# Test against North Europe
./inv.sh --inventory-file test_inventories/inventory_diverse_arg.json \
         --target-region northeurope \
         --all \
         --source-region centralus

# Test against East US
./inv.sh --inventory-file test_inventories/inventory_diverse_arg.json \
         --target-region eastus \
         --all \
         --source-region centralus
```

## Troubleshooting

### Test Fails on "inv.sh execution failed"

Check the e2e test log:

```bash
cat test_e2e/e2e_run.log
```

Common issues:
- Azure CLI authentication error — Run `az login` first
- Missing prerequisites — Ensure `jq` is installed
- Invalid region name — Check target region is valid

### Cache Not Reusing

If Test 8 fails to detect cache reuse:

```bash
# Check cache directory
ls -lh .cache/

# Verify cache files exist
ls -l .cache/skus_*.json
```

Cache may not be reused if:
- Cache directory was cleaned between runs
- TTL (24 hours) expired
- API responses changed

### Resource Counts Don't Match

Check inventory file was ingested correctly:

```bash
jq '.data | length' test_e2e/test_inventory.json
cat output/source_inventory_summary.csv | wc -l
```

## Performance Characteristics

| Phase | Cold Run | Cached Run | Notes |
|-------|----------|-----------|-------|
| Inventory Load | <1ms | <1ms | File I/O |
| SKU Fetching | 15-30s | <1s | API calls vs cache |
| Availability Check | 20-40s | <5s | Parallel lookups |
| Total | 40-60s | 5-10s | Depends on region |

## Integration with CI/CD

Use e2e test in automated pipelines:

```bash
#!/bin/bash
set -e

# Run e2e validation
./tests/e2e_test.sh

# Check test results
if [ -f test_e2e/report.txt ]; then
    echo "E2E Test Passed ✓"
    cat test_e2e/report.txt
else
    echo "E2E Test Failed ✗"
    exit 1
fi
```

## Next Steps

- **Customize Inventory** — Add your own resources to test_inventories
- **Add More AI Services** — Include more Cognitive Services variants
- **Test Additional Regions** — Validate multi-region deployments
- **Performance Tuning** — Analyze cache hit rates and optimize

## Support

For issues or questions about the e2e test:

1. Check the test log: `test_e2e/e2e_run.log`
2. Review test report: `test_e2e/report.txt`
3. Inspect output files: `output/*.json`, `output/*.csv`
4. Check Azure login: `az account show`
