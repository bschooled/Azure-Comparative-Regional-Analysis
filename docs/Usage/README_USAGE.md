# Azure Comparative Regional Analysis

A fast, reliable automation tool using Azure CLI and REST APIs to:
1. Enumerate resources in a source Azure region with quantities
2. Enrich them with pricing meters (Service Name, Service Family, Meter Name)
3. Determine if equivalent resource types/SKUs are available in a target region

## Features

- **Fast Resource Discovery**: Uses Azure Resource Graph (ARG) for scalable cross-subscription queries
- **Pricing Enrichment**: Integrates with Azure Retail Prices API to map resources to pricing meters
- **Availability Checking**: Validates resource SKU availability in target regions
- **Flexible Scoping**: Support for tenant-wide, management group, and resource group scopes
- **Performance Optimized**: Parallel API calls with caching and retry logic
- **Comprehensive Reporting**: Generates CSV and JSON outputs for analysis

## Prerequisites

- **Azure CLI** v2.50 or higher
- **jq** for JSON processing
- **curl** for HTTP requests
- **Azure Login**: Authenticated with `az login`
- **Permissions**: Reader role (or higher) across target scope(s)

## Installation

1. Clone this repository
2. Make the main script executable:
   ```bash
   chmod +x inv.sh
   chmod +x examples/*.sh
   ```

## Usage

### Basic Syntax

```bash
./inv.sh --source-region <region> --target-region <region> [SCOPE] [OPTIONS]
```

### Required Arguments

- `--source-region <region>`: Source Azure region (e.g., `eastus`)
- `--target-region <region>`: Target Azure region for comparison (e.g., `westeurope`)

### Scope (one required)

- `--all`: Query all accessible subscriptions in tenant
- `--mg <managementGroupId>`: Query resources within a management group
- `--rg <subId:rgName>`: Query resources within a specific resource group

### Optional Arguments

- `--subscriptions <csv>`: Comma-separated subscription IDs (overrides `--all`)
- `--resource-types <csv>`: Filter by resource types
- `--parallel <n>`: Concurrency for API calls (default: 8)
- `--cache-dir <path>`: Directory for caching API responses (default: `./.cache`)

## Examples

### Example 1: Tenant-wide Analysis

```bash
./inv.sh --all \
  --source-region eastus \
  --target-region westeurope \
  --parallel 12
```

### Example 2: Management Group Scope

```bash
./inv.sh --mg Contoso-Prod \
  --source-region eastus2 \
  --target-region uksouth
```

### Example 3: Resource Group Scope

```bash
./inv.sh --rg 00000000-0000-0000-0000-000000000000:WorkloadRG \
  --source-region westus3 \
  --target-region centralus
```

### Example 4: Filtered by Resource Type

```bash
./inv.sh --all \
  --source-region eastus \
  --target-region westeurope \
  --resource-types "Microsoft.Compute/virtualMachines,Microsoft.Storage/storageAccounts"
```

## Output Files

All output files are written to the `output/` directory:

| File | Description |
|------|-------------|
| `source_inventory.json` | Raw Azure Resource Graph output for resources in source region |
| `source_inventory_summary.csv` | Summarized resource counts by type, SKU, and properties |
| `price_lookup.csv` | Pricing meter mappings (serviceName, serviceFamily, meterName, etc.) |
| `target_region_availability.json` | Availability status for each resource type/SKU in target region |
| `service_availability_comparison.csv` | Cross-region availability comparison table (CSV format) |
| `service_availability_comparison.json` | Cross-region availability comparison table (JSON format) |
| `availability_summary.txt` | Human-readable availability summary with statistics |
| `unpriced_resources.json` | Resources that could not be mapped to pricing meters |
| `run.log` | Detailed execution log with timing and error information |

## Output Schema

### source_inventory_summary.csv

```csv
subscriptionId,resourceGroup,location,type,sku,vmSize,diskSku,diskSizeGB,count
```

### price_lookup.csv

```csv
type,armSkuName,armRegionName,serviceName,serviceFamily,meterName,productName,skuName,unitOfMeasure,retailPrice,currencyCode
```

### target_region_availability.json

```json
[
  {
    "type": "Microsoft.Compute/virtualMachines",
    "armSkuName": "Standard_D8s_v5",
    "targetRegion": "westeurope",
    "available": true,
    "restrictions": []
  }
]
```

### service_availability_comparison.csv

Cross-region availability comparison showing each service type and whether it's available in the source and target regions:

```csv
ServiceType,SKU/Name,eastusAvailable,eastusDetails,westeuropeAvailable,westeuropeDetails
Microsoft.Compute/virtualMachines,Standard_D2s_v5,YES,Found in inventory,true,Available
Microsoft.Storage/storageAccounts,Standard_LRS,YES,Found in inventory,true,Available
```

### service_availability_comparison.json

Rich JSON format with detailed availability information per region and service type.

## Performance Optimization

The tool includes several performance optimizations:

- **Single ARG Query**: One large query per scope instead of multiple small ones
- **Region Filtering**: ARG queries filtered by region to reduce payload
- **Caching**: API responses cached to avoid repeated fetches (24-hour TTL)
- **Parallel Processing**: Configurable parallelism for pricing lookups
- **Retry Logic**: Exponential backoff for transient API failures

## Architecture

```
inv.sh (main entry point)
├── lib/args.sh              - Argument parsing and validation
├── lib/utils_log.sh         - Logging and error handling
├── lib/utils_cache.sh       - Caching utilities
├── lib/utils_http.sh        - HTTP retry and pagination
├── lib/inventory.sh         - Azure Resource Graph queries
├── lib/data_processing.sh   - Summarization and tuple extraction
├── lib/pricing.sh           - Retail Prices API integration
├── lib/availability.sh      - SKU availability checking
└── lib/comparative_analysis.sh - Cross-region comparison tables
```

## Error Handling

The script exits with non-zero status on:
- ARG query failures
- Missing/invalid arguments
- Authentication issues
- Excessive pricing lookup failures

Warnings are issued for:
- Resources without direct pricing meters
- Resources unavailable in target region
- Cache misses or expired entries

## Cache Management

Cache files are stored in `.cache/` by default with a 24-hour TTL:
- Compute SKU listings by region
- Storage SKU listings
- Provider resource type locations
- Pricing API responses

To clear cache:
```bash
rm -rf .cache/*
```

## Troubleshooting

### "Not logged in to Azure"
Run `az login` to authenticate

### "jq not found"
Install jq: `sudo apt-get install jq` (Ubuntu/Debian) or `brew install jq` (macOS)

### "ARG query failed"
Check permissions - you need Reader role or higher

### "Some resources could not be priced"
Check `output/unpriced_resources.json` - some resources don't have direct meters

## Contributing

This tool is designed for Principal Solutions Engineers to assist with Azure migration and cost analysis projects.

## License

See LICENSE file for details.

## References

- [Azure Resource Graph Documentation](https://learn.microsoft.com/en-us/azure/governance/resource-graph/)
- [Azure Retail Prices API](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)
- [Azure VM SKUs](https://learn.microsoft.com/en-us/rest/api/compute/resource-skus/list)
- [Products Available by Region](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/)
