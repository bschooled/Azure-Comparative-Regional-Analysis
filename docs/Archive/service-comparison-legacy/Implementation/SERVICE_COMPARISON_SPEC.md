# Service Comparison Feature Specification

## Executive Summary
The Service Comparison feature enables Azure administrators and architects to discover and compare all available Azure services and their SKUs across two regions. This feature provides insights into regional service availability gaps and helps identify migration readiness between regions.

## 1. Feature Overview

### Purpose
- Discover all available Azure services in source and target regions
- Identify service family and SKU availability differences
- Generate comparative analysis reports for decision-making
- Support regional migration planning and service deployment strategies

### Scope
The feature covers:
- **Service Discovery**: All publicly available Azure services (excluding marketplace-only)
- **SKU Enrichment**: Detailed SKU information for:
  - Compute (VMs, disks, scale sets, galleries)
  - Storage (all storage account types and tiers)
  - Databases (SQL, MySQL, PostgreSQL, CosmosDB)
  - Fabric (capacity SKUs)
  - Other major service categories
- **Comparative Analysis**: Service family counts, SKU availability, regional gaps
- **Output Formats**: CSV, JSON, and interactive shell display

### Out of Scope
- Marketplace services
- Preview services (unless explicitly flagged)
- Pricing comparison (separate from service availability)
- Performance/SLA comparison
- Regional restriction details (cached as metadata)

## 2. Requirements

### Functional Requirements

#### FR-1: Service Discovery
- The system shall enumerate all resource providers available in a specified region
- The system shall group services by logical service family (compute, storage, database, etc.)
- The system shall exclude marketplace-only and deprecated services by default
- The system shall cache service metadata to minimize API calls

#### FR-2: SKU Population
- For Compute services: Query VM SKUs, disk types, scale set configurations
- For Storage services: Query storage account tiers (Standard, Premium, GPv2, etc.)
- For Database services: Query database SKUs and editions available in each region
- For Fabric services: Query capacity SKU availability
- The system shall maintain region-specific caches to avoid redundant queries

#### FR-3: Comparative Analysis
- Compare service availability between source and target regions
- Identify services/SKUs available only in source region
- Identify services/SKUs available only in target region
- Calculate summary statistics (counts, gaps, match percentage)
- Flag regional restrictions and limitations

#### FR-4: Output Generation
- Generate CSV format for spreadsheet analysis
- Generate JSON format for programmatic integration
- Display interactive shell summary with key metrics
- Include metadata (generation time, source/target regions, counts)

#### FR-5: Performance & Reliability
- Cache all API responses to reduce redundant calls
- Implement exponential backoff for API rate limiting
- Handle API failures gracefully with fallbacks
- Complete full comparison in < 5 minutes with cold cache
- Support concurrent operations without race conditions

### Non-Functional Requirements

#### NFR-1: Performance
- API call rate: Maximum 10 requests per 10 seconds (Resource Graph limit)
- Response time: < 300ms per service category query
- Total execution: < 5 minutes for full regional comparison
- Cache hit reduces execution to < 30 seconds

#### NFR-2: Reliability
- 99% success rate for service discovery
- Handle Azure API throttling (HTTP 429) gracefully
- Validate all cached data before use
- Log all errors with timestamp and context

#### NFR-3: Maintainability
- Reuse existing libraries (utils_log.sh, utils_cache.sh, display.sh)
- Modular functions for independent testing
- Clear separation between discovery, analysis, and output
- Comprehensive documentation for each function

#### NFR-4: Usability
- Simple CLI interface with clear help messages
- Sensible defaults for optional parameters
- Progress feedback during long operations
- Clear error messages with suggested fixes

## 3. Design & Architecture

### Component Architecture
```
┌─────────────────────────────────┐
│   services_compare.sh (Main)    │ - CLI entry point
│   - Parse arguments             │ - Orchestration
│   - Validate inputs             │ - Output generation
└──────────────┬──────────────────┘
               │
        ┌──────▼──────────────────────────┐
        │  lib/service_comparison.sh      │ - Core logic
        │  - Service discovery functions  │ - SKU queries
        │  - Comparative analysis         │ - Output generators
        └──────┬───────────────────────────┘
               │
        ┌──────┴────────────────────────────┐
        │     Imported Libraries             │
        ├─────────────────────────────────┤
        │ - lib/utils_log.sh   (Logging)  │
        │ - lib/utils_cache.sh (Caching)  │
        │ - lib/display.sh     (Output)   │
        │ - lib/data_processing.sh (CSV)  │
        └─────────────────────────────────┘
               │
        ┌──────▼──────────────────────────┐
        │    External APIs                 │
        ├─────────────────────────────────┤
        │ - Azure CLI (az command)        │
        │ - Azure Resource Manager REST   │
        │ - Resource Graph API            │
        └─────────────────────────────────┘
```

### Data Flow

1. **Input**: User specifies source and target regions
2. **Discovery Phase**:
   - Query service providers for source region
   - Query service providers for target region
   - Cache service metadata
3. **SKU Enrichment Phase**:
   - For each service category, fetch SKU details
   - Map SKUs to region availability
   - Cache SKU metadata
4. **Analysis Phase**:
   - Compare service availability
   - Compare SKU availability
   - Calculate summary statistics
5. **Output Phase**:
   - Generate CSV report
   - Generate JSON report
   - Display shell summary

### API Integration Strategy

#### Azure CLI Commands
```bash
az provider list --expand "resourceTypes/locations"
az vm list-skus --location <region>
az storage sku list
az sql db list-editions --location <region>
```

#### Azure REST APIs (Fallbacks)
```
GET /subscriptions/{subscriptionId}/providers/Microsoft.Compute/skus
GET /subscriptions/{subscriptionId}/providers/Microsoft.Fabric/skus
GET /subscriptions/{subscriptionId}/providers/Microsoft.Storage/skus
```

#### Rate Limiting Strategy
- Resource Graph: 10 requests per 10 seconds → Use 1 second delay between requests
- Retail Prices API: 1000 per hour → Cache aggressively (24 hour TTL)
- Implement exponential backoff: 1s, 2s, 4s, 8s (max 3 retries)

### Caching Strategy
```
Cache Structure:
.cache/
├── services_eastus (TTL: 24h)
├── services_westeurope (TTL: 24h)
├── compute_skus_eastus (TTL: 24h)
├── compute_skus_westeurope (TTL: 24h)
├── storage_skus_eastus (TTL: 24h)
├── storage_skus_westeurope (TTL: 24h)
├── database_skus_eastus (TTL: 24h)
└── database_skus_westeurope (TTL: 24h)
```

Each cache entry includes:
- Timestamp (for TTL validation)
- Data (JSON)
- Hash (for integrity verification)

## 4. Implementation Details

### File Structure
```
Azure-Comparative-Regional-Analysis/
├── services_compare.sh                 # Main script
├── lib/
│   ├── service_comparison.sh          # Core library (NEW)
│   ├── utils_log.sh                   # Logging (existing)
│   ├── utils_cache.sh                 # Caching (existing)
│   ├── display.sh                     # Display (existing)
│   └── data_processing.sh             # CSV processing (existing)
├── tests/
│   ├── test_services_compare.sh       # Unit tests (NEW)
│   └── test_services_e2e.sh           # E2E tests (NEW)
├── docs/
│   ├── Features/
│   │   └── SERVICE_COMPARISON.md      # Feature guide (NEW)
│   └── Implementation/
│       └── SERVICE_COMPARISON_SPEC.md # This file (NEW)
└── output/
    ├── services_comparison.csv         # CSV output
    ├── services_comparison.json        # JSON output
    └── services_comparison.log         # Execution log
```

### Function API

#### Public Functions (in lib/service_comparison.sh)

```bash
# Service Discovery
get_providers_in_region(region)
  Returns: JSON array of providers with resource types
  
get_service_families(region)
  Returns: JSON object with services grouped by family

# SKU Discovery
get_compute_skus(region)
  Returns: JSON array of Compute SKUs
  
get_storage_skus(region)
  Returns: JSON array of Storage SKUs
  
get_database_skus(region)
  Returns: JSON array of Database SKUs
  
get_fabric_skus(region)
  Returns: JSON array of Fabric SKUs

# Comparative Analysis
compare_services(source_region, target_region)
  Returns: JSON object with service comparison
  
compare_skus(source_region, target_region, category)
  Returns: JSON object with SKU comparison for category

# Output Generation
generate_comparison_csv(source_region, target_region, output_file)
  Generates CSV file with comparison results
  
generate_comparison_json(source_region, target_region, output_file)
  Generates JSON file with detailed comparison
```

### Error Handling

| Error Case | Handling | Recovery |
|-----------|----------|----------|
| Invalid region | Log error, exit with code 1 | User must provide valid region |
| API throttling (429) | Exponential backoff | Automatic retry up to 3 times |
| API failure (5xx) | Log warning, fallback | Try alternate API method |
| Cache corruption | Log error, clear cache | Fetch fresh data |
| Missing authentication | Log error, exit | User must authenticate with `az login` |
| Insufficient permissions | Log warning, skip service | Continue with other services |

### Logging Strategy
- **ERROR**: Critical failures that stop execution
- **WARN**: Non-critical issues (skipped services, API fallbacks)
- **INFO**: Progress milestones (service discovery complete, CSV generated)
- **DEBUG**: Detailed operation info (cache hit/miss, API calls)

## 5. Output Specifications

### CSV Output Format
**services_comparison.csv**
```csv
ServiceFamily,SourceCount,TargetCount,OnlyInSource,OnlyInTarget,Status
Compute,150,148,2,0,PARTIAL_MATCH
Storage,5,5,0,0,FULL_MATCH
Database,20,18,2,1,PARTIAL_MATCH
...
```

### JSON Output Format
**services_comparison.json**
```json
{
  "metadata": {
    "sourceRegion": "eastus",
    "targetRegion": "westeurope",
    "generatedAt": "2025-01-15T10:30:00Z",
    "categories": ["compute", "storage", "database", "fabric", "network", "containers", "analytics"]
  },
  "comparisons": {
    "compute": {
      "category": "compute",
      "sourceCount": 150,
      "targetCount": 148,
      "common": 148,
      "onlyInSource": ["Standard_D4s_v3", "..."],
      "onlyInTarget": []
    },
    "storage": {
      "category": "storage",
      "sourceCount": 5,
      "targetCount": 5,
      "common": 5,
      "onlyInSource": [],
      "onlyInTarget": []
    }
  }
}
```

### Shell Display Format
```
═════════════════════════════════════════════════════
  SERVICE COMPARISON SUMMARY
═════════════════════════════════════════════════════
Source Region: eastus
Target Region: westeurope

Comparison Results:
─────────────────────────────────────────────────────
SERVICE    SRC   TGT  ONLY_SRC  ONLY_TGT  STATUS
Compute    150   148     2         0      PARTIAL_MATCH
Storage      5     5     0         0      FULL_MATCH
Database    20    18     2         1      PARTIAL_MATCH
...

Summary:
  Full Match:      3
  Partial Match:   4
  Extended:        1
  Not Available:   2
```

## 6. Testing Strategy

### Unit Tests
- Service discovery functions (mocked API responses)
- SKU queries (mocked API responses)
- Comparative analysis functions
- Output generation functions

### Integration Tests
- Real API calls with test regions
- Cache validation and expiration
- Error handling and recovery

### Performance Tests
- Execution time benchmarks
- API call counting
- Cache efficiency metrics

### Regression Tests
- Service comparison consistency across versions
- Output format backward compatibility

## 7. Deployment & Rollout

### Phase 1: Development (Sprint 1)
- ✓ Core library implementation
- ✓ Main script skeleton
- Feature documentation

### Phase 2: Testing (Sprint 2)
- Unit test implementation
- Integration test execution
- Performance validation

### Phase 3: Documentation (Sprint 3)
- Usage guide
- Troubleshooting guide
- API documentation

### Phase 4: Release (Sprint 4)
- Code review and approval
- Tagged release
- User communication

## 8. Success Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| Functional Completeness | 100% | All FR requirements met |
| Code Coverage | >80% | Unit tests coverage |
| Performance | <5 min | Execution time (cold cache) |
| Reliability | >99% | Success rate across regions |
| User Satisfaction | >4/5 | User feedback surveys |
| Documentation | Complete | All docs reviewed and approved |

## 9. Known Limitations & Future Work

### Current Limitations
1. Some resource providers don't fully populate location lists
2. Preview services excluded by default
3. Marketplace services require separate discovery
4. Performance data not included (separate feature)

### Future Enhancements
- Real-time pricing comparison
- Service SLA comparison
- Feature availability comparison
- Automated migration readiness scoring
- Integration with other tools (Azure Advisor, etc.)
- Web dashboard for visualization
- Scheduled comparison reports
