# Service Comparison Feature

## Overview
The Service Comparison feature provides a full service comparison between two Azure regions, enumerating all available services, their SKUs, and highlighting differences in service families and SKU availability.

## Purpose
- **Service Discovery**: Fetch all available Azure services in source and target regions
- **SKU Enrichment**: For services with region-specific SKUs (Compute, Storage, Databases, Fabric), populate detailed SKU information
- **Comparative Analysis**: Identify service family and SKU availability differences between regions
- **Output Formats**: CSV for spreadsheet analysis, JSON for programmatic use, shell display for quick summary

## Feature Requirements

### Core Functionality
1. **Service Discovery**
   - Fetch all Azure services available in source region
   - Fetch all Azure services available in target region
   - Exclude marketplace-only services
   - Group services into logical service families

2. **SKU Population**
   - For Compute (VirtualMachines, Disks, VMAre Scale Sets, etc.): Query SKU availability per region
   - For Storage (all tiers): Query storage account SKU availability
   - For Databases (SQL, MySQL, PostgreSQL, CosmosDB): Query database SKU/tier availability
   - For Fabric: Query capacity SKU availability
   - Cache results to minimize API calls and respect rate limits

3. **Comparative Analysis**
   - Count service families in each region
   - Count total SKUs in each region
   - Identify services/SKUs available in source but not target
   - Identify services/SKUs available in target but not source
   - Identify regional restrictions or limitations

4. **Output Generation**
   - **Shell Display**: Summary with counts, top differences, highlighted gaps
   - **CSV Format**: Structured data for Excel/Sheets analysis
   - **JSON Format**: Hierarchical service/SKU structure for programmatic use

### Performance Considerations
- **API Rate Limits**: Azure enforces strict rate limits on Resource Graph and Retail Prices APIs
  - Resource Graph: ~10 requests/10 seconds per tenant
  - Retail Prices: ~1000 requests/hour
  - Solution: Implement intelligent caching, batch queries, exponential backoff
  
- **Query Optimization**
  - Use provider-specific SKU endpoints (faster than generic queries)
  - Batch multiple resource type queries
  - Leverage existing cache from inventory operations
  
- **Execution Time Target**: < 5 minutes per region pair with cold cache

### Scope
- **Supported Service Categories**
  - Compute (VMs, disks, galleries, scale sets, etc.)
  - Storage (blob, file, table, queue, data lake)
  - Databases (SQL, MySQL, PostgreSQL, CosmosDB, Managed databases)
  - Analytics (Synapse, Databricks, Data Factory)
  - Networking (VNets, Load Balancers, Application Gateway, etc.)
  - Containers (AKS, Container Registry, Container Instances)
  - AI/ML (Cognitive Services, Machine Learning, Search)
  - Integration (Event Hubs, Service Bus, API Management)
  - Other specialized services

- **Exclusions**
  - Marketplace-only services
  - Preview/deprecated services (optional flag to include)
  - Internal/hidden resource types

## Data Flow

```
┌─────────────────────────────────────────────────┐
│ Fetch Available Services (both regions)          │
│ - Query Resource Providers                       │
│ - Filter by region availability                  │
└──────────────┬──────────────────────────────────┘
               │
        ┌──────▼──────────┐
        │ Group Services  │
        │ by Family       │
        └──────┬──────────┘
               │
        ┌──────▼──────────────────────────┐
        │ For each service family:        │
        │ - Query provider-specific SKUs  │
        │ - Map to regions                │
        │ - Cache results                 │
        └──────┬──────────────────────────┘
               │
        ┌──────▼──────────────────────────┐
        │ Comparative Analysis            │
        │ - Count differences             │
        │ - Identify gaps                 │
        │ - Build summary statistics      │
        └──────┬──────────────────────────┘
               │
  ┌────────────┼────────────┐
  │            │            │
┌─▼──────┐ ┌──▼──────┐ ┌───▼────┐
│ Shell  │ │  CSV    │ │  JSON  │
│Display │ │ Output  │ │ Output │
└────────┘ └─────────┘ └────────┘
```

## Implementation Strategy

### Phase 1: Core Service Discovery (v1.0)
- Create `lib/service_comparison.sh` with core service discovery functions
- Implement caching mechanism for service metadata
- Build CSV/JSON output generators
- Create `services_compare.sh` main orchestration script

### Phase 2: SKU Enrichment (v1.1)
- Add Compute SKU population
- Add Storage SKU population
- Add Database SKU population
- Implement intelligent caching to avoid redundant API calls

### Phase 3: Comparative Analysis (v1.2)
- Build diff analysis engine
- Generate summary statistics
- Create shell display formatter

### Phase 4: Testing & Optimization (v1.3)
- Comprehensive test coverage
- API rate limit testing
- Performance optimization
- Documentation

## File Outputs

### CSV Outputs
**services_source_region.csv**
```
ServiceFamily,ProviderName,ResourceType,SKUsAvailable,Restrictions
Compute,Microsoft.Compute,virtualMachines,150,None
Storage,Microsoft.Storage,storageAccounts,5,"GPv2 not in all zones"
```

**services_comparison.csv**
```
ServiceFamily,SourceCount,TargetCount,OnlyInSource,OnlyInTarget,Status
Compute,150,148,"Standard_D4s_v3","",PARTIAL
Storage,5,5,"","",FULL_MATCH
```

### JSON Outputs
**services_full_comparison.json**
```json
{
  "metadata": {
    "sourceRegion": "eastus",
    "targetRegion": "westeurope",
    "generatedAt": "2025-01-15T10:30:00Z",
    "serviceCount": 45,
    "skuCount": 1250
  },
  "serviceComparison": {
    "compute": {
      "provider": "Microsoft.Compute",
      "sourceSKUs": 150,
      "targetSKUs": 148,
      "gaps": ["Standard_D4s_v3"]
    }
  }
}
```

## Usage Examples

### Basic service comparison
```bash
./services_compare.sh --source-region eastus --target-region westeurope
```

### With caching
```bash
./services_compare.sh --source-region eastus --target-region westeurope --cache-dir /tmp/svc_cache
```

### With specific service families
```bash
./services_compare.sh --source-region eastus --target-region westeurope --services "compute,storage,database"
```

### Generate JSON only
```bash
./services_compare.sh --source-region eastus --target-region westeurope --output-format json --output-dir /custom/output
```

## Dependencies
- Azure CLI (az command)
- jq (JSON processing)
- curl (HTTP requests, for Retail Prices API)
- Existing libraries: `lib/display.sh`, `lib/data_processing.sh`, `lib/utils_cache.sh`

## Testing Strategy
- Unit tests for service discovery functions
- Integration tests with real Azure APIs (against test subscriptions)
- Performance tests with various region combinations
- Cache validation tests
- Error handling tests (API failures, rate limiting)

## Known Limitations
1. Some resource providers don't fully populate location lists
2. Preview services may not have stable SKU APIs
3. Marketplace-only services require separate discovery mechanism
4. Some regional restrictions aren't captured in SKU metadata

## Future Enhancements
- Real-time pricing comparison
- Service SLA comparison
- Feature availability comparison
- Support matrix generation
- Automated migration readiness assessment
