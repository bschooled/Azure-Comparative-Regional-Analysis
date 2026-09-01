# SKU Population - Quick Reference

## At a Glance

### What Changed?
- **Before**: 4 service types (Compute, Storage, Database, Fabric)
- **After**: 10 comprehensive categories covering **ALL Azure services**

### New Service Categories Added
✅ **Networking** - Load Balancers, Application Gateway, Firewall, VPN, NAT Gateway  
✅ **AI (Expanded)** - All Cognitive Services, OpenAI, Machine Learning  
✅ **Databases (Expanded)** - SQL, PostgreSQL, MySQL, CosmosDB, Redis (all variants)  
✅ **Analytics (Expanded)** - Synapse, Data Factory, Kusto, Databricks (all services)  
✅ **Containers (New)** - AKS, Container Registry, Container Instances  
✅ **Serverless (New)** - Functions, App Service, Logic Apps, Container Apps  
✅ **Monitoring (New)** - Log Analytics, Application Insights, Monitoring  
✅ **Integration (New)** - Service Bus, Event Hubs, Event Grid  

---

## Quick Commands

### List What's Available
```bash
# See all service categories
./lib/sku_query.sh list-categories

# See providers for a category
./lib/sku_query.sh list-providers ai

# View complete catalog
./lib/sku_query.sh catalog
```

### Query SKUs
```bash
# Single category, single region
./lib/sku_query.sh query ai westus2

# All categories, single region
./lib/sku_query.sh query-all eastus

# List SKU names only
./lib/sku_query.sh list databases swedencentral
```

### Compare Regions
```bash
# JSON comparison
./lib/sku_query.sh compare ai westus2 norwayeast

# Human-readable report
./lib/sku_query.sh report databases eastus swedencentral

# Check specific SKU
./lib/sku_query.sh check compute Standard_D4s_v5 swedencentral
```

---

## Service Category Cheat Sheet

| Category | Provider(s) | Example SKUs |
|----------|------------|--------------|
| **compute** | Microsoft.Compute | Standard_B2ms, Standard_D4s_v5 |
| **storage** | Microsoft.Storage | Standard_LRS, Premium_ZRS |
| **networking** | Microsoft.Network | Standard, Premium, WAF_v2 |
| **databases** | Sql, DBforPostgreSQL,<br>DBforMySQL, DocumentDB, Cache | GP_Gen5_2, Hyperscale_8vCore,<br>Standard, P3 |
| **analytics** | Synapse, DataFactory,<br>Kusto, Databricks | DW100c, Large, E16s_v5 |
| **ai** | CognitiveServices,<br>MachineLearningServices | S0, Standard_NC24ads_A100_v4 |
| **containers** | ContainerService,<br>ContainerRegistry, ContainerInstance | Standard_DS2_v2, Premium, B1s |
| **serverless** | Web, App | P1v3, Consumption, D1 |
| **monitoring** | OperationalInsights,<br>Insights | PerGB2018, Standard |
| **integration** | ServiceBus,<br>EventHub, EventGrid | Standard, Premium, Basic |

---

## Common Workflows

### Migration Planning
```bash
#!/bin/bash
# Check if all required SKUs are available in target region

CATEGORIES="compute storage databases ai"
SOURCE="eastus"
TARGET="swedencentral"

for cat in $CATEGORIES; do
    ./lib/sku_query.sh report "$cat" "$SOURCE" "$TARGET" > "migration_${cat}.txt"
done

echo "Migration reports generated!"
```

### Availability Check
```bash
# Check multiple SKUs at once
for sku in Standard_D4s_v5 Standard_D8s_v5 Standard_D16s_v5; do
    if ./lib/sku_query.sh check compute "$sku" norwayeast; then
        echo "✓ $sku available"
    else
        echo "✗ $sku NOT available"
    fi
done
```

### Export to CSV
```bash
# Query and convert to CSV
./lib/sku_query.sh query ai westus2 | \
    jq -r '.[] | [.name, .tier, .provider] | @csv' > ai_skus.csv
```

---

## Programmatic Usage

### In Shell Scripts
```bash
#!/bin/bash
source lib/sku_query_engine.sh

# Query category
result_file=$(query_category_skus "ai" "westus2")

# Process results
ai_skus=$(jq -r '.[] | .name' "$result_file")

# Check availability
if check_category_sku_availability "ai" "S0" "norwayeast"; then
    echo "OpenAI available in Norway East"
fi
```

### Integration Example
```bash
# Use in inventory analysis
source lib/sku_query_engine.sh

analyze_inventory() {
    local inventory_file="$1"
    local target_region="$2"
    
    # Extract unique SKUs from inventory
    local skus=$(jq -r '.resources[].sku' "$inventory_file" | sort -u)
    
    # Check each SKU
    echo "Checking $target_region availability..."
    for sku in $skus; do
        if ! check_category_sku_availability "compute" "$sku" "$target_region"; then
            echo "WARNING: $sku not available in $target_region"
        fi
    done
}
```

---

## Performance Tips

### Caching
- First query: ~30 seconds (API calls)
- Cached queries: ~2 seconds (local reads)
- Cache expires: 24 hours (configurable)

```bash
# Increase cache duration
export CACHE_EXPIRY_HOURS=48

# Custom cache location
export CACHE_DIR="/tmp/sku_cache"
```

### Parallel Queries
```bash
# Query multiple categories in parallel
{
    ./lib/sku_query.sh query compute eastus > compute.json &
    ./lib/sku_query.sh query storage eastus > storage.json &
    ./lib/sku_query.sh query ai eastus > ai.json &
    wait
}
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "No SKUs retrieved" | Provider may not support `/skus` endpoint - check catalog |
| "Invalid category" | Run `list-categories` for valid options |
| "Not logged in" | Run `az login` |
| "Rate limit" | Use cache or wait 1-2 minutes |
| Slow queries | Enable caching with `export CACHE_DIR=.cache` |

### Debug Mode
```bash
export LOG_LEVEL=DEBUG
./lib/sku_query.sh query ai westus2 2>&1 | tee debug.log
```

---

## Files Created

### Core Libraries
- `lib/service_catalog.sh` - Service-to-provider mappings
- `lib/sku_query_engine.sh` - High-level orchestration
- `lib/sku_provider.sh` - Generic SKU fetching (existing)

### CLI Tool
- `sku_query.sh` - Command-line interface

### Documentation
- `docs/COMPREHENSIVE_SKU_GUIDE.md` - Full guide (this file's parent)
- `docs/SKU_QUICK_REFERENCE.md` - This quick reference

---

## Key Innovations

### 1. Generic Provider Pattern
Single function works for **any** Azure provider:
```bash
fetch_provider_skus "Microsoft.CognitiveServices" "2024-04-01-preview"
fetch_provider_skus "Microsoft.Synapse" "2021-06-01"
```

### 2. Category-Based Abstraction
Users don't need to know provider names:
```bash
./lib/sku_query.sh query ai westus2  # Queries both CognitiveServices AND MachineLearning
```

### 3. Multi-Provider Aggregation
Single query returns SKUs from multiple providers:
```bash
# Databases = Sql + DBforPostgreSQL + DBforMySQL + DocumentDB + Cache
./lib/sku_query.sh query databases eastus
```

---

## Next Steps

1. **Test the System**
   ```bash
   ./lib/sku_query.sh list-categories
   ./lib/sku_query.sh catalog
   ./lib/sku_query.sh query ai westus2
   ```

2. **Run a Comparison**
   ```bash
   ./lib/sku_query.sh report databases eastus norwayeast
   ```

3. **Integrate with Existing Scripts**
   ```bash
   source lib/sku_query_engine.sh
   # Use functions in your scripts
   ```

---

## Support

- Full Guide: [docs/COMPREHENSIVE_SKU_GUIDE.md](COMPREHENSIVE_SKU_GUIDE.md)
- Provider Reference: [docs/SKU_PROVIDER_GUIDE.md](SKU_PROVIDER_GUIDE.md)
- Issues: Contact repository maintainer

---

**Version**: 2.0  
**Last Updated**: 2025-01-23  
**Coverage**: 10 service categories, 20+ Azure providers
