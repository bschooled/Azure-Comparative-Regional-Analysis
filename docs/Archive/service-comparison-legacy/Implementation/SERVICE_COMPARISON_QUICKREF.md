# Service Comparison - Quick Reference

## File Locations
| File | Purpose |
|------|---------|
| `services_compare.sh` | Main entry point script |
| `lib/service_comparison.sh` | Core library with all functions |
| `docs/Features/SERVICE_COMPARISON.md` | Feature overview |
| `docs/Implementation/SERVICE_COMPARISON_SPEC.md` | Detailed specification |
| `docs/Implementation/SERVICE_COMPARISON_IMPLEMENTATION.md` | Implementation guide |
| `output/services_comparison.csv` | CSV comparison output |
| `output/services_comparison.json` | JSON comparison output |

## Quick Commands

### Basic Comparison
```bash
./services_compare.sh --source-region eastus --target-region westeurope
```

### CSV Only
```bash
./services_compare.sh --source-region eastus --target-region westeurope --output-formats csv
```

### JSON Only
```bash
./services_compare.sh --source-region eastus --target-region westeurope --output-formats json
```

### Custom Cache Directory
```bash
./services_compare.sh --source-region eastus --target-region westeurope \
  --cache-dir /tmp/azure_cache --output-dir ./reports
```

### List Available Regions
```bash
az account list-locations --query "[].name" -o tsv | sort
```

### Clear Cache
```bash
rm -rf .cache
```

## Output Formats

### CSV Structure
```
ServiceFamily | SourceCount | TargetCount | OnlyInSource | OnlyInTarget | Status
Compute      | 150         | 148         | 2            | 0            | PARTIAL_MATCH
```

### JSON Structure
```json
{
  "metadata": {
    "sourceRegion": "eastus",
    "targetRegion": "westeurope",
    "generatedAt": "2025-01-15T10:30:00Z"
  },
  "comparisons": {
    "compute": {
      "sourceCount": 150,
      "targetCount": 148,
      "onlyInSource": ["SKU1", "SKU2"],
      "onlyInTarget": []
    }
  }
}
```

## Common Queries

### Extract Compute SKU Gaps
```bash
jq '.comparisons.compute.onlyInSource[]' output/services_comparison.json
```

### Find Full Matches
```bash
awk -F',' '$NF == "FULL_MATCH"' output/services_comparison.csv
```

### Count Gaps by Category
```bash
jq '.comparisons | to_entries[] | {
  category: .key,
  gaps: (.value.onlyInSource | length)
}' output/services_comparison.json
```

### Total SKU Counts
```bash
jq '.comparisons | to_entries[] | .value.sourceCount' output/services_comparison.json | awk '{s+=$1} END {print "Total:", s}'
```

## Environment Variables

### Cache Configuration
```bash
export SC_CACHE_TTL_SERVICES=86400    # 24 hours
export SC_CACHE_TTL_SKUS=86400        # 24 hours
export CACHE_DIR=.cache               # Cache directory
```

### API Configuration
```bash
export SC_API_DELAY_MS=500            # 500ms between API calls
export SC_MAX_RETRIES=3               # 3 retries on failure
```

## Supported Regions
Azure regions are continuously added. For current list:
```bash
az account list-locations --query "[].name" -o tsv | sort
```

Common regions:
- `eastus` - US East
- `westeurope` - West Europe
- `eastasia` - East Asia
- `southeastasia` - Southeast Asia
- `uksouth` - UK South
- `canadacentral` - Canada Central
- `australiaeast` - Australia East
- `japaneast` - Japan East
- `centralindia` - Central India
- `southcentralus` - South Central US

## Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| `No subscriptions found` | Run `az login` |
| `Invalid region` | Check region name with `az account list-locations` |
| `API throttling` | Increase `SC_API_DELAY_MS` to 1000 |
| `Cache errors` | Delete `.cache` directory and retry |
| `Permission denied` | Check subscription access with `az role assignment list` |
| `API 429 errors` | Automatic retry; wait if persistent |

## Performance Tips

1. **Use Cache**: First run takes 4-5 minutes, subsequent < 1 minute
2. **Batch Operations**: Run multiple region pairs without clearing cache
3. **Off-Peak Execution**: Run during non-business hours for faster API responses
4. **Parallel Regions**: Use separate terminal windows for different region pairs

## Integration Examples

### Generate Report
```bash
./services_compare.sh --source-region eastus --target-region westeurope \
  --output-dir ./reports --output-formats csv,json
echo "Report generated in ./reports/"
```

### Pipeline Integration
```bash
#!/bin/bash
for target_region in westeurope southeastasia japaneast; do
  echo "Comparing eastus to $target_region..."
  ./services_compare.sh --source-region eastus --target-region "$target_region" \
    --output-dir "./reports/$target_region"
done
```

### Monitor for Changes
```bash
#!/bin/bash
NEW_REPORT=$(./services_compare.sh --source-region eastus --target-region westeurope | jq .)
OLD_REPORT=$(cat last_report.json 2>/dev/null || echo "{}")

if [ "$NEW_REPORT" != "$OLD_REPORT" ]; then
  echo "Service availability changed!"
  echo "$NEW_REPORT" > last_report.json
fi
```

## Help & Support

### View Help
```bash
./services_compare.sh --help
```

### Enable Verbose Logging
```bash
./services_compare.sh --source-region eastus --target-region westeurope --verbose
```

### Check Script Permissions
```bash
ls -la services_compare.sh lib/service_comparison.sh
# Should show: -rwxr-xr-x (executable)
```

### Verify Dependencies
```bash
which az    # Azure CLI
which jq    # JSON processor
which curl  # HTTP client (for REST APIs)
```

## Advanced Usage

### Custom Output Processing
```bash
# Extract all compute gaps and format as table
jq -r '.comparisons.compute.onlyInSource[]' output/services_comparison.json | \
  column -t -N "SKU" > compute_gaps.txt

# Generate HTML report from JSON
jq -r '.comparisons | to_entries[] | 
  "<tr><td>\(.key)</td><td>\(.value.sourceCount)</td></tr>"' \
  output/services_comparison.json > report.html
```

### Automated Scheduling
```bash
# Add to crontab for weekly comparisons
0 2 * * 0 /home/user/Azure-Comparative-Regional-Analysis/services_compare.sh \
  --source-region eastus --target-region westeurope \
  --output-dir /home/user/weekly_reports/$(date +\%Y\%m\%d)
```

### Notifications
```bash
# Send email with gaps
if jq '.comparisons.compute.onlyInSource | length > 0' output/services_comparison.json; then
  echo "Compute SKU gaps found!" | mail -s "Azure Service Changes" admin@example.com
fi
```
