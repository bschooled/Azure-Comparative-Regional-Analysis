# Quick Start Guide

## Prerequisites Check

```bash
# Verify Azure CLI
az --version

# Verify jq
jq --version

# Login to Azure
az login
```

## Quick Examples

### 1. Analyze Single Resource Group
```bash
./inv.sh \
  --rg YOUR_SUB_ID:YOUR_RG_NAME \
  --source-region eastus \
  --target-region westeurope
```

### 2. Analyze All Subscriptions
```bash
./inv.sh \
  --all \
  --source-region eastus \
  --target-region westeurope
```

### 3. Focus on Compute Resources Only
```bash
./inv.sh \
  --all \
  --source-region eastus \
  --target-region westeurope \
  --resource-types "Microsoft.Compute/virtualMachines,Microsoft.Compute/disks"
```

## Understanding the Output

### 1. Check the Summary
```bash
# View resource counts
cat output/source_inventory_summary.csv

# Top resource types
tail -n +2 output/source_inventory_summary.csv | cut -d',' -f4 | sort | uniq -c | sort -rn | head -10
```

### 2. Review Regional Comparison
```bash
# View cross-region availability comparison
cat output/service_availability_comparison.csv

# Human-readable summary
cat output/availability_summary.txt

# Detailed JSON comparison
jq '.[] | {serviceType: .serviceType, inventoryCount: .inventoryCount, availability: .availability}' \
  output/service_availability_comparison.json
```

### 3. Review Pricing
```bash
# View pricing data
cat output/price_lookup.csv

# Check for unpriced resources
jq '.[] | .type' output/unpriced_resources.json | sort | uniq
```

### 4. Check Availability
```bash
# See unavailable resources
jq '.[] | select(.available == false)' output/target_region_availability.json

# Count availability
jq '[.[] | select(.available == true)] | length' output/target_region_availability.json
```

## Performance Tips

- Use `--parallel 12` or higher on fast connections
- Use `--cache-dir` to preserve cache between runs
- Filter by `--resource-types` to reduce processing time
- Cache is valid for 24 hours

## Common Issues

### Issue: Too many pricing lookups
**Solution**: Use `--resource-types` to filter

### Issue: Slow ARG queries
**Solution**: This is normal for large estates; ARG is optimized but may take time

### Issue: Cache too large
**Solution**: Clear cache with `rm -rf .cache/*`

## Next Steps After Running

1. Review `output/run.log` for execution details
2. Analyze `output/source_inventory_summary.csv` for resource distribution
3. Compare regional availability using `output/availability_summary.txt`
4. View detailed comparison in `output/service_availability_comparison.csv`
5. Check `output/target_region_availability.json` for migration blockers
6. Use `output/price_lookup.csv` for cost estimation
