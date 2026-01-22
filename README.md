# Azure Comparative Regional Analysis

A comprehensive automation tool that inventories Azure resources in a source region, maps them to pricing meters, checks availability in a target region, and generates cross-region comparison tables.

## Quick Overview

**Problem:** Planning an Azure regional migration but need to know:
- What resources exist in the source region?
- What SKUs are available in the target region?
- Which resources/SKUs are incompatible with the target region?
- What are the pricing differences across regions?

**Solution:** This tool answers all these questions with automated analysis and detailed comparison tables.

## Key Features

- **Fast Discovery**: Uses Azure Resource Graph for scalable cross-subscription queries
- **Pricing Enrichment**: Integrates with Azure Retail Prices API for cost analysis
- **Availability Checking**: Validates resource SKU availability in target regions
- **Comparative Tables**: Generates cross-region service availability comparison
- **Shell Display**: Prints comprehensive summary directly to terminal ⭐ NEW
- **Multiple Formats**: CSV, JSON, and text outputs for different use cases
- **Flexible Scoping**: Support for tenant-wide, management group, and resource group analysis
- **Performance Optimized**: Parallel API calls, caching, and retry logic

## Output Files

After running the tool, you'll get:

1. **source_inventory.json** - Raw Azure resources from the source region
2. **source_inventory_summary.csv** - Resource counts by type and SKU
3. **price_lookup.csv** - Pricing meter mappings for all resources
4. **target_region_availability.json** - SKU availability in target region
5. **service_availability_comparison.csv** - Quick reference comparison table ⭐ NEW
6. **service_availability_comparison.json** - Rich metadata comparison ⭐ NEW
7. **availability_summary.txt** - Human-readable summary report ⭐ NEW

`services_compare.sh` (region-only comparison) produces:

- `<source>_vs_<target>_providers.json` (JSON source-of-truth)
- `<source>_vs_<target>_providers.csv` (SKU-granular CSV derived from JSON)

## Quick Start

```bash
# Inventory-driven analysis (ARG + pricing + availability + comparative tables)
./inv.sh --all --source-region eastus --target-region westeurope

# Inventory-driven analysis for a specific resource group
./inv.sh --rg <subId>:<rgName> --source-region eastus --target-region westeurope

# Region-only comparison (no inventory)
./services_compare.sh --source-region westus2 --target-region swedencentral
```

### Comparative Analyis - Example

You can quickly gain insights by generating your inventory and utilizing the comparative_analysis.sh tool.
The extensive list is available in the output json and csv files which will be created in the output folder for your own analysis.

**Example of existing usage in Central US and seeing if I have any gaps**
Redirect to a text file to read the full output.
```text
═══════════════════════════════════════════════════════════════════════════════
MICROSOFT.STORAGE - ACCOUNT TYPE COMPARISON
═══════════════════════════════════════════════════════════════════════════════

Status: FULL_MATCH
SKU Counts: centralus=26, swedencentral=26

Account Types (centralus | swedencentral):
─────────────────────────────────────────────────────────────────────────────
BlobStorage                       3 | 3
BlockBlobStorage                  2 | 2
FileStorage                       8 | 8
Storage                           5 | 5
StorageV2                         8 | 8

═══════════════════════════════════════════════════════════════════════════════
PROVIDERS WITH NOTABLE DIFFERENCES (Top 15)
═══════════════════════════════════════════════════════════════════════════════

Format: Provider | Source Count | Target Count | Difference | Status
─────────────────────────────────────────────────────────────────────────────
Microsoft.Compute                    1135 |  1043 |    92 | SOURCE_EXTENDED
Microsoft.Storage                      26 |    26 |     0 | FULL_MATCH
Microsoft.Compute/disks                 7 |     7 |     0 | FULL_MATCH

═══════════════════════════════════════════════════════════════════════════════
Full comparison data available in:
  JSON: output/inventory_centralus_vs_swedencentral_providers.json
  CSV:  output/inventory_centralus_vs_swedencentral_providers.csv
═══════════════════════════════════════════════════════════════════════════════
```

See [docs/Usage/QUICKSTART.md](docs/Usage/QUICKSTART.md) for walkthrough examples.

## More Examples

### Inventory scopes

```bash
# Management group scope
./inv.sh --mg <managementGroupId> --source-region eastus2 --target-region uksouth

# Resource group scope
./inv.sh --rg <subId>:<rgName> --source-region westus3 --target-region centralus
```

### Use a pre-generated inventory

```bash
# Skip ARG discovery and use an existing inventory JSON
./inv.sh --all --source-region centralus --target-region swedencentral \
    --inventory-file test_inventories/inventory_compute.json
```

### Filter resource types (inventory workflow)

```bash
./inv.sh --all --source-region eastus --target-region westeurope \
    --resource-types "Microsoft.Compute/virtualMachines,Microsoft.Compute/disks"
```

### Region-only comparison outputs

```bash
./services_compare.sh --source-region westus2 --target-region swedencentral --output-dir output
```

### Output Examples

Example of full Services comparison between West US 2 and Sweden Central. 
**Your own analysis may return slightly different results, this is due to subscription level enablement of services**

```text
==============================
SERVICE COMPARISON SUMMARY
==============================
Source Region: westus2
Target Region: swedencentral

Top 20 providers by SKU gaps (prioritizing Compute):
─────────────────────────────────────────────────────────────────
Provider               Gap  OnlySrc  OnlyTgt  SrcSKUs  TgtSKUs  Status
Compute                118  104      14       1071     981      SOURCE_EXTENDED
DBforPostgreSQL        54   0        54       0        54       SOURCE_RESTRICTED
Sql                    26   26       0        170      144      SOURCE_EXTENDED
Kusto                  20   16       4        40       28       SOURCE_EXTENDED
AnalysisServices       11   11       0        11       0        SOURCE_EXTENDED
DevCenter              11   0        11       0        11       TARGET_EXTENDED
DBforMySQL             9    9        0        60       51       SOURCE_EXTENDED
AVS                    4    4        0        16       12       SOURCE_EXTENDED
DataMigration          4    4        0        4        0        SOURCE_EXTENDED
OnlineExperimentation  4    0        4        0        4        TARGET_EXTENDED
Workloads              4    4        0        4        0        SOURCE_EXTENDED
CognitiveServices      3    3        0        12       9        SOURCE_EXTENDED
ApiManagement          1    1        0        8        7        TARGET_EXTENDED
Experimentation        1    1        0        1        0        SOURCE_EXTENDED
Synapse                1    1        0        2        1        SOURCE_EXTENDED

Provider status summary:
  AVAILABLE_NO_SKUS: 292
  FULL_MATCH: 8
  SOURCE_EXTENDED: 12
  SOURCE_RESTRICTED: 1
  TARGET_EXTENDED: 4
```
The below example shows output from **inv.sh**, which filters on your own resouces. It also analyzes quota usage in source and target region.
```text
╔══════════════════════════════════════════════════════════════════════════════╗
║ SERVICE QUOTA ANALYSIS                                                        ║
╠══════════════════════════════════════════════════════════════════════════════╣
✓  All resources will fit within target quota

  Top 5 Quota Consumers in Source Region:
    Standard BS Family vCPUs                        24 / 100   24% used
    Total Regional vCPUs                            24 / 100   24% used
    Total Regional Low-priority vCPUs                0 / 100    0% used
    Virtual Machines                                 9 / 25000   0% used
    Availability Sets                                0 / 2500   0% used

  ✓  158 quota metrics available

  Target Region Status:
  ℹ  Target region quota data ready for analysis
╚══════════════════════════════════════════════════════════════════════════════╝


╔══════════════════════════════════════════════════════════════════════════════╗
║ AVAILABILITY IN TARGET REGION: swedencentral                                  ║
╠══════════════════════════════════════════════════════════════════════════════╣
  Service Types Checked:                   26
  Available in Target:                     26
  ✓  All service types available in target region
╚══════════════════════════════════════════════════════════════════════════════╝


╔══════════════════════════════════════════════════════════════════════════════╗
║ COMPARATIVE REGIONAL ANALYSIS                                                 ║
╠══════════════════════════════════════════════════════════════════════════════╣
     Service Types Analyzed:                  23
  ✓  23 services available in both regions
  Total Resources in Source:               0
╚══════════════════════════════════════════════════════════════════════════════╝
```

## Documentation

- [Quick Start](docs/Usage/QUICKSTART.md) - Common scenarios and output review
- [Inventory Workflow](docs/Usage/README_USAGE.md) - Full `inv.sh` usage and outputs
- [Region-Only Comparison](docs/Usage/SERVICES_COMPARE.md) - Full `services_compare.sh` usage and outputs

## Requirements

- Azure CLI v2.50+
- jq for JSON processing
- curl for HTTP requests
- Reader role or higher in Azure

## Architecture

The tool runs in 5 phases:

```
Phase 1: Resource Inventory (Azure Resource Graph)
    ↓
Phase 2: Inventory Summarization
    ↓
Phase 3: Pricing Enrichment (Retail Prices API)
    ↓
Phase 4: Availability Checking
    ↓
Phase 5: Comparative Regional Analysis ← NEW
```

See [docs/Usage/README_USAGE.md](docs/Usage/README_USAGE.md) for full architecture details.
