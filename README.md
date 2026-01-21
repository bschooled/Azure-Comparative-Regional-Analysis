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

## Quick Start

```bash
# Tenant-wide analysis
./inv.sh --all --source-region eastus --target-region westeurope

# Specific resource group
./inv.sh --rg <subId>:<rgName> --source-region eastus --target-region westeurope
```

See [docs/Usage/QUICKSTART.md](docs/Usage/QUICKSTART.md) for detailed examples.

## Documentation

- [Usage Guide](docs/Usage/README_USAGE.md) - Complete user guide with examples
- [Quick Start](docs/Usage/QUICKSTART.md) - Quick start guide and common scenarios
- [Features Overview](docs/Features/FEATURE_SUMMARY.md) - Feature details and capabilities

For detailed architecture, implementation details, troubleshooting guides, and reference materials, see [docs/README.md](docs/README.md).

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

## Recent Updates

✨ **NEW - Phase 5: Comparative Regional Analysis**
- Cross-region service availability comparison tables
- Multiple output formats (CSV, JSON, Text)
- Service inventory counts and statistics
- Restriction and limitation tracking
- See [docs/Features/FEATURE_SUMMARY.md](docs/Features/FEATURE_SUMMARY.md) for details

## For More Information

- **Usage Guide**: See [docs/Usage/README_USAGE.md](docs/Usage/README_USAGE.md)
- **Quick Examples**: See [docs/Usage/QUICKSTART.md](docs/Usage/QUICKSTART.md)  
- **Feature Details**: See [docs/Features/COMPARATIVE_ANALYSIS.md](docs/Features/COMPARATIVE_ANALYSIS.md)
- **Full Documentation Index**: See [docs/README.md](docs/README.md)
- **Original Spec**: See [docs/Spec.md](docs/Spec.md)
