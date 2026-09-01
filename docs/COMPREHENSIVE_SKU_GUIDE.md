# Comprehensive SKU Population Guide

## Overview

The Azure Comparative Regional Analysis toolkit now supports comprehensive SKU population across **all major Azure service categories**, not just the originally limited 4 types. This expansion provides complete coverage for:

- ✅ **Compute** - VMs, VM Scale Sets, Dedicated Hosts
- ✅ **Storage** - Blob, Files, Disks, NetApp  
- ✅ **Networking** - Load Balancers, Application Gateway, Firewall, VPN
- ✅ **Databases (All)** - SQL Server, PostgreSQL, MySQL, CosmosDB, Redis
- ✅ **Analytics/Fabric (All)** - Synapse, Data Factory, Kusto, Databricks
- ✅ **AI Services (All)** - Cognitive Services, OpenAI, Machine Learning
- ✅ **Containerization (All)** - AKS, Container Registry, Container Instances
- ✅ **Serverless (All)** - Functions, App Service, Logic Apps, Container Apps
- ✅ **Monitoring** - Log Analytics, Application Insights, Monitoring
- ✅ **Integration** - Service Bus, Event Hubs, Event Grid

## Architecture

### Three-Layer Design

```
┌─────────────────────────────────────────────────────────┐
│                    SKU Query CLI                        │
│          (lib/sku_query.sh - User Interface)            │
└────────────────────┬────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────────┐
│               SKU Query Engine                          │
│         (lib/sku_query_engine.sh - Orchestration)       │
│  • Category-based queries                               │
│  • Multi-provider aggregation                           │
│  • Regional comparison                                  │
└────────────────────┬────────────────────────────────────┘
                     │
     ┌───────────────┴───────────────┐
     │                               │
┌────▼──────────────┐    ┌──────────▼─────────────────────┐
│ Service Catalog   │    │   Generic SKU Provider         │
│ (service_catalog) │    │   (sku_provider.sh)            │
│                   │    │                                │
│ • Provider maps   │    │ • REST API queries             │
│ • API versions    │    │ • Response caching             │
│ • Resource types  │    │ • Regional filtering           │
└───────────────────┘    └────────────────────────────────┘
```

### Component Descriptions

#### 1. Service Catalog (`lib/service_catalog.sh`)
Defines mappings between service categories and Azure resource providers:

```bash
# Example mappings
SERVICE_PROVIDERS[ai]="Microsoft.CognitiveServices Microsoft.MachineLearningServices"
SERVICE_API_VERSIONS[Microsoft.CognitiveServices]="2024-04-01-preview"
SERVICE_RESOURCE_TYPES[Microsoft.CognitiveServices]="accounts,commitmentPlans"
```

**Key Features:**
- 10 major service categories
- 20+ Azure resource providers
- Latest API versions (2024-2025)
- Resource type metadata

#### 2. Generic SKU Provider (`lib/sku_provider.sh`)
Universal SKU fetching mechanism for any Azure provider:

```bash
# Generic fetch that works for any provider
fetch_provider_skus "Microsoft.Storage" "2023-01-01"
fetch_provider_skus "Microsoft.CognitiveServices" "2024-04-01-preview"
fetch_provider_skus "Microsoft.Synapse" "2021-06-01"
```

**Key Features:**
- Single API pattern for all providers
- Automatic response normalization
- Intelligent caching
- Regional filtering

#### 3. SKU Query Engine (`lib/sku_query_engine.sh`)
High-level orchestration and aggregation:

```bash
# Category-based queries
query_category_skus "ai" "eastus"
query_multi_category_skus "compute storage networking" "swedencentral"

# Comparison between regions
compare_category_skus_between_regions "databases" "eastus" "norwayeast"
```

**Key Features:**
- Multi-provider aggregation
- Cross-region comparison
- Availability checking
- Structured reporting

#### 4. SKU Query CLI (`lib/sku_query.sh`)
User-friendly command-line interface:

```bash
# Simple commands
./lib/sku_query.sh list-categories
./lib/sku_query.sh query ai westus2
./lib/sku_query.sh compare databases eastus swedencentral
```

## Usage Examples

### 1. List Available Service Categories

```bash
./lib/sku_query.sh list-categories
```

**Output:**
```
Available Service Categories:
==============================

  compute         Compute (VMs, VM Scale Sets)
  storage         Storage (Blob, Files, Disks)
  networking      Networking (Load Balancers, Firewall, VPN)
  databases       Databases (SQL, PostgreSQL, MySQL, CosmosDB)
  analytics       Analytics/Fabric (Synapse, Data Factory)
  ai              AI Services (Cognitive Services, OpenAI, ML)
  containers      Containers (AKS, ACR, ACI)
  serverless      Serverless (Functions, App Service, Container Apps)
  monitoring      Monitoring (Log Analytics, App Insights)
  integration     Integration (Service Bus, Event Hub)
```

### 2. Query AI Service SKUs

```bash
./lib/sku_query.sh query ai westus2 > ai_skus_westus2.json
```

**Output** (JSON):
```json
[
  {
    "name": "S0",
    "tier": "Standard",
    "kind": "OpenAI",
    "locations": ["westus2"],
    "provider": "Microsoft.CognitiveServices",
    "category": "ai",
    "capabilities": [
      {"name": "GPT-4", "value": "true"},
      {"name": "GPT-35-Turbo", "value": "true"}
    ]
  },
  {
    "name": "Standard_NC24ads_A100_v4",
    "tier": "Standard",
    "size": "NC24ads_A100_v4",
    "locations": ["westus2"],
    "provider": "Microsoft.MachineLearningServices",
    "category": "ai"
  }
  ...
]
```

### 3. Compare Database SKUs Between Regions

```bash
./lib/sku_query.sh compare databases eastus swedencentral
```

**Output** (JSON):
```json
{
  "category": "databases",
  "source_region": "eastus",
  "target_region": "swedencentral",
  "source_count": 234,
  "target_count": 198,
  "source_only": [
    "Standard_M128ms_v2",
    "Hyperscale_8vCore_Gen5",
    ...
  ],
  "target_only": [
    "Basic_B2s",
    ...
  ],
  "common": [
    "Standard_D2s_v3",
    "GP_Gen5_2",
    ...
  ]
}
```

### 4. Generate Human-Readable Report

```bash
./lib/sku_query.sh report ai westus2 norwayeast
```

**Output:**
```
==================================================
SKU Availability Report
Category: AI Services (Cognitive Services, OpenAI, ML)
Source Region: westus2
Target Region: norwayeast
==================================================

Summary:
  Source SKUs: 156
  Target SKUs: 89
  Common SKUs: 87
  Source Only: 69
  Target Only: 2

SKUs NOT available in target region:
  - S0 (OpenAI GPT-4)
  - Standard_NC96ads_A100_v4
  - Premium_P3
  ...

SKUs ONLY available in target region:
  - Basic_B1
  - Standard_E2s_v5
```

### 5. Check Specific SKU Availability

```bash
./lib/sku_query.sh check compute Standard_D4s_v5 swedencentral
```

**Output:**
```
✓ SKU 'Standard_D4s_v5' is AVAILABLE in swedencentral
```

### 6. List All SKUs for a Category

```bash
./lib/sku_query.sh list ai westus2 | grep -i "gpt"
```

**Output:**
```
S0 (OpenAI GPT-4)
S0 (OpenAI GPT-3.5-Turbo)
Standard_S0_GPT4
```

### 7. Query All Services

```bash
./lib/sku_query.sh query-all eastus > all_skus_eastus.json
```

Retrieves SKUs across **all 10 service categories** in a single query.

### 8. View Service Catalog

```bash
./lib/sku_query.sh catalog
```

**Output:**
```
==================================================
Azure Service Catalog
==================================================

[compute] Compute (VMs, VM Scale Sets)
  → Provider: Microsoft.Compute
    API Version: 2024-03-01
    Resource Types: virtualMachines,virtualMachineScaleSets,disks,snapshots

[ai] AI Services (Cognitive Services, OpenAI, ML)
  → Provider: Microsoft.CognitiveServices
    API Version: 2024-04-01-preview
    Resource Types: accounts,commitmentPlans
  → Provider: Microsoft.MachineLearningServices
    API Version: 2024-04-01
    Resource Types: workspaces,computeInstances,computeClusters
...
```

## Integration with Regional Analysis

### Use in Regional Comparison Scripts

```bash
#!/bin/bash
# Example: Compare all services between two regions

SOURCE_REGION="eastus"
TARGET_REGION="swedencentral"

# Query all categories
for category in compute storage networking databases analytics ai containers serverless monitoring integration; do
    echo "Analyzing $category..."
    
    ./lib/sku_query.sh report "$category" "$SOURCE_REGION" "$TARGET_REGION" \
        > "reports/${category}_comparison.txt"
done

echo "All reports generated in reports/ directory"
```

### Programmatic Usage in Shell Scripts

```bash
#!/bin/bash
# Source the libraries directly
source lib/sku_query_engine.sh

# Check if AI SKUs are available before migration
check_ai_migration() {
    local target_region="$1"
    local required_skus=(
        "S0"
        "Standard_NC24ads_A100_v4"
        "Premium_P3"
    )
    
    local missing=()
    
    for sku in "${required_skus[@]}"; do
        if ! check_category_sku_availability "ai" "$sku" "$target_region"; then
            missing+=("$sku")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required AI SKUs in $target_region:"
        printf '  - %s\n' "${missing[@]}"
        return 1
    fi
    
    echo "✓ All required AI SKUs available in $target_region"
    return 0
}

# Example usage
check_ai_migration "norwayeast"
```

## Provider Coverage

### Complete Provider Mapping

| Service Category | Azure Providers | Resource Types |
|-----------------|----------------|----------------|
| **Compute** | Microsoft.Compute | VMs, VMSS, Disks, Snapshots |
| **Storage** | Microsoft.Storage | Storage Accounts |
| **Networking** | Microsoft.Network | LB, AppGW, Firewall, VPN, NAT |
| **Databases** | Microsoft.Sql<br>Microsoft.DBforPostgreSQL<br>Microsoft.DBforMySQL<br>Microsoft.DocumentDB<br>Microsoft.Cache | SQL Server, MI, Elastic Pools<br>Flexible Servers, Hyperscale<br>Flexible Servers<br>CosmosDB, Cassandra, Mongo<br>Redis, Redis Enterprise |
| **Analytics** | Microsoft.Synapse<br>Microsoft.DataFactory<br>Microsoft.Kusto<br>Microsoft.Databricks | Workspaces, SQL/Spark/Kusto Pools<br>Factories, Integration Runtimes<br>Clusters<br>Workspaces |
| **AI** | Microsoft.CognitiveServices<br>Microsoft.MachineLearningServices | Accounts, Commitment Plans<br>Workspaces, Compute |
| **Containers** | Microsoft.ContainerService<br>Microsoft.ContainerRegistry<br>Microsoft.ContainerInstance | Managed Clusters, Agent Pools<br>Registries<br>Container Groups |
| **Serverless** | Microsoft.Web<br>Microsoft.App | App Service Plans, Functions<br>Container Apps, Environments |
| **Monitoring** | Microsoft.OperationalInsights<br>Microsoft.Insights | Workspaces, Clusters<br>App Insights, Action Groups |
| **Integration** | Microsoft.ServiceBus<br>Microsoft.EventHub<br>Microsoft.EventGrid | Namespaces<br>Namespaces, Clusters<br>Topics, Domains |

### API Version Strategy

All API versions are **latest stable or preview** as of 2024-2025:

- Most providers: 2024-xx-xx or 2025-xx-xx
- Preview features: Uses `-preview` suffix when needed
- Backward compatibility: Works with older API versions via configuration

## Performance & Caching

### Intelligent Caching System

```bash
# Cache structure
.cache/
├── skus_microsoftcompute.json          # Compute SKUs (all regions)
├── skus_microsoftcognitiveservices.json # AI SKUs (all regions)
├── skus_microsoftcompute_eastus.json    # Region-specific cache
└── fetch.log                            # API call logs
```

**Cache Benefits:**
- ✅ Reduces API calls by 90%+
- ✅ Faster repeated queries (1-2 seconds vs 10-30 seconds)
- ✅ Respects Azure API rate limits
- ✅ Automatic cache expiration (configurable)

**Cache Configuration:**
```bash
export CACHE_EXPIRY_HOURS=24  # Default: 24 hours
export CACHE_DIR=".cache"      # Cache location
```

## Advanced Features

### 1. Multi-Category Queries

```bash
# Query multiple categories at once
source lib/sku_query_engine.sh

result_file=$(query_multi_category_skus "compute storage networking" "eastus")
jq '.' "$result_file"
```

### 2. Custom Filtering

```bash
# Filter by provider
./lib/sku_query.sh query databases eastus | \
    jq '.[] | select(.provider == "Microsoft.DocumentDB")'

# Filter by tier
./lib/sku_query.sh query compute westus2 | \
    jq '.[] | select(.tier == "Standard")'
```

### 3. Export Formats

```bash
# JSON (default)
./lib/sku_query.sh query ai westus2 > ai_skus.json

# CSV conversion
./lib/sku_query.sh query compute eastus | \
    jq -r '.[] | [.name, .tier, .provider] | @csv' > compute_skus.csv

# Table format
./lib/sku_query.sh list ai westus2 | column -t
```

## Troubleshooting

### Common Issues

**1. "No SKUs retrieved for provider"**
```
Cause: Provider doesn't support /skus REST API endpoint
Solution: Check if provider uses alternative SKU query method
```

**2. "Invalid category"**
```
Cause: Typo in category name
Solution: Run ./lib/sku_query.sh list-categories to see valid options
```

**3. "Could not retrieve subscription ID"**
```
Cause: Not logged into Azure CLI
Solution: az login
```

**4. "API rate limit exceeded"**
```
Cause: Too many API calls in short time
Solution: Use cached results or increase cache expiry time
```

### Debug Mode

```bash
# Enable verbose logging
export LOG_LEVEL=DEBUG

# Run query with debug output
./lib/sku_query.sh query ai westus2 2>&1 | tee debug.log
```

### Cache Management

```bash
# Clear all cached SKUs
rm -rf .cache/skus_*.json

# Clear specific provider cache
rm .cache/skus_microsoftcognitiveservices.json

# View cache statistics
ls -lh .cache/skus_*.json
```

## Future Enhancements

Planned improvements:

1. **Pricing Integration** - Add pricing data to SKU queries
2. **Quota Checking** - Check regional quotas alongside SKU availability
3. **Recommendations** - Suggest alternative SKUs when unavailable
4. **Migration Planning** - Generate complete migration plans
5. **Web UI** - Interactive dashboard for SKU exploration

## Contributing

### Adding New Service Categories

1. Edit `lib/service_catalog.sh`:

```bash
# Add new category
SERVICE_PROVIDERS[iot]="Microsoft.Devices Microsoft.IoTHub"
SERVICE_API_VERSIONS[Microsoft.Devices]="2023-06-30"
SERVICE_RESOURCE_TYPES[Microsoft.Devices]="iothubs,provisioningServices"
```

2. Update `get_category_display_name()` function

3. Test the new category:

```bash
./lib/sku_query.sh list-providers iot
./lib/sku_query.sh query iot eastus
```

### Adding New Providers

1. Research the provider's REST API:
   - `/skus` endpoint support
   - Latest API version
   - Resource types available

2. Add to service catalog with appropriate mappings

3. Validate with test queries

## Resources

- [Azure REST API Documentation](https://docs.microsoft.com/en-us/rest/api/azure/)
- [Azure Resource Provider Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/management/azure-services-resource-providers)
- [SKU Provider Implementation Guide](../docs/SKU_PROVIDER_GUIDE.md)

## License

Same as parent project - see LICENSE file.
