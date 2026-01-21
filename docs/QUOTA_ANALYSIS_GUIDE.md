# Service Quota Analysis Feature

## Overview

The quota analysis feature intelligently fetches service quotas for resources found in your inventory, providing visibility into:

- **Subscription-level quotas** (e.g., total vCores, storage accounts)
- **Resource family quotas** (e.g., vCores per VM family)
- **Per-region quotas** (source region and target region)
- **Quota utilization** (current usage vs. limits)

## When Quota Analysis Runs

Quota fetching is **automatically enabled** for these scopes:

- ✅ **Per-subscription** (when using `--all` or explicit `--subscriptions`)
- ✅ **Per-resource-group** (when using `--rg subId:rgName`)
- ❌ **Tenant-wide** (when using `--all` without filtering)

For resource group scopes, subscription-level quota is fetched for context.

## How It Works

### 1. **Service Mapping**
Each resource type in your inventory is automatically mapped to its quota endpoints:
- VMs → Compute vCore quotas
- Storage Accounts → Storage account quotas
- Databases → Database server and vCore quotas
- AKS → Container service quotas
- And more...

### 2. **Intelligent Deduplication**
The system avoids redundant API calls:
- Fetches subscription-level quotas **once**
- Then fetches per-family quotas (e.g., per VM family)
- Merges results intelligently

### 3. **Multi-Region Fetching**
- **Source Region**: Fetches quotas for your current region
- **Target Region**: Fetches quotas for comparison region (when appropriate)
- Enables cross-region quota comparison

### 4. **Graceful Fallback**
- Services without quota APIs are silently skipped
- Partial quota data still generates output
- No failures if quota API is unavailable

## Output Files

### `quota_source_region.json`
Detailed quota data for resources in source region:
```json
[
  {
    "resourceType": "microsoft.compute/virtualmachines",
    "endpoint": "compute.vcpu",
    "region": "swedencentral",
    "quotas": [
      {
        "name": {
          "value": "cores",
          "localizedValue": "Total Regional vCores"
        },
        "limit": 100,
        "currentValue": 45
      }
    ]
  }
]
```

### `quota_target_region.json`
Same structure as source, but for target region. Allows quota comparison across regions.

### `quota_summary.csv`
Aggregated quota metrics in CSV format:
```
region,resourceType,quotaMetric,limit,currentUsage,availableQuota,percentUsed
swedencentral,microsoft.compute/virtualmachines,Total Regional vCores,100,45,55,45
westeurope,microsoft.compute/virtualmachines,Total Regional vCores,200,120,80,60
```

## Usage Examples

### Example 1: Check Quotas for Per-Subscription Analysis
```bash
./inv.sh --subscriptions 00000000-0000-0000-0000-000000000000 \
         --source-region eastus \
         --target-region westeurope
```

**Outputs:**
- `quota_source_region.json` — Quotas in eastus
- `quota_target_region.json` — Quotas in westeurope
- `quota_summary.csv` — Comparison table

### Example 2: Check Quotas for Resource Group
```bash
./inv.sh --rg 00000000-0000-0000-0000-000000000000:MyResourceGroup \
         --source-region centralus \
         --target-region northeurope
```

**What happens:**
- Fetches subscription-level quotas (context for resource group)
- Compares with target region quotas

### Example 3: View Quota Summary
```bash
cat output/quota_summary.csv | column -t -s,

# Output:
# region        resourceType                        quotaMetric              limit currentUsage availableQuota percentUsed
# swedencentral microsoft.compute/virtualmachines   Total Regional vCores   100   45           55             45
# swedencentral microsoft.storage/storageaccounts   Storage Accounts        250   180          70             72
```

### Example 4: Check Specific Service Quota
```bash
jq '.[] | select(.resourceType == "microsoft.compute/virtualmachines")' \
   output/quota_source_region.json | jq '.quotas[]'
```

## Supported Services

Quota data is available for:

| Service | Quota Types |
|---------|------------|
| **Compute** | vCore Total, vCore per Family, Disk quotas |
| **Storage** | Storage Account count, Capacity limits |
| **Network** | Load Balancers, Public IPs, NAT Gateways, App Gateways |
| **Databases** | SQL Database count, DTU quotas, vCore quotas |
| **PostgreSQL** | Flexible Server count, vCore quotas |
| **MySQL** | Flexible Server count, vCore quotas |
| **Cosmos DB** | Account count, Throughput quotas |
| **Cache** | Redis cache instances |
| **Containers** | AKS cluster count, vCore quotas |
| **App Service** | App Service Plan count, Instance limits |
| **Key Vault** | Key Vault count |

## API Integration

The quota system uses:

1. **Azure Compute Usages API** (`/providers/Microsoft.Compute/locations/{location}/usages`)
   - Most comprehensive quota coverage
   - Covers compute, storage, and related resources

2. **Resource-Specific APIs**
   - Service-specific quota endpoints when available
   - Gracefully falls back if unavailable

## Performance

- **First run**: 5-15 seconds (API calls to fetch quota data)
- **Cached runs**: <1 second (quota data cached)
- **Cache TTL**: 24 hours
- **API calls**: ~1-3 per subscription (minimal overhead)

## Troubleshooting

### Issue: No quota data in output files

**Cause**: Quota APIs may not be available for your subscription/region combination

**Solution**: 
1. Verify scope is per-subscription or per-resource-group
2. Check Azure CLI login: `az account show`
3. Verify subscription has resources: `az resource list --query 'length([])' | grep -v 0`

### Issue: Quota data missing for specific service

**Cause**: Service doesn't have exposed quota APIs

**Solution**:
1. Check supported services list above
2. File feature request for additional quota APIs
3. Use alternative monitoring tools for that service

### Issue: Cross-region quota comparison shows zero

**Cause**: Service may not be available in target region

**Solution**: 
1. Check availability results in `target_region_availability.json`
2. Ensure target region supports the service
3. Verify subscription has quota in target region

## Advanced Usage

### Filter quota by resource type
```bash
jq '.[] | select(.resourceType | contains("compute"))' \
   output/quota_source_region.json
```

### Calculate quota utilization percentage
```bash
jq '.[] | .quotas[] | {
  metric: .name.localizedValue,
  utilization: ((.currentValue / .limit) * 100 | round)
}' output/quota_source_region.json
```

### Identify over-quota or near-limit services
```bash
jq '.[] | .quotas[] | select((.limit - .currentValue) < 10) | {
  metric: .name.localizedValue,
  remaining: (.limit - .currentValue)
}' output/quota_source_region.json
```

## API Limits

Azure quota APIs have these characteristics:

- **Rate limit**: Up to 500 requests per minute per subscription
- **Response size**: Typically <1 MB per request
- **Timeout**: 30 seconds per request
- **Cache**: Recommended 24-hour cache (to respect rate limits)

The system implements caching to respect these limits.

## Security Considerations

- Quota data requires **Reader** role (read-only)
- No modifications made to subscriptions
- Data cached locally in `.cache/` directory
- No credentials stored in output files
- All API calls use Azure CLI authentication

## Future Enhancements

Planned additions to quota analysis:

1. **Quota alerts** — Flag resources approaching limits
2. **Quota forecasting** — Predict when quotas might be exceeded
3. **Multi-subscription quota** — Aggregate across subscriptions
4. **Quota optimization** — Recommend quota adjustments
5. **Historical tracking** — Track quota trends over time
