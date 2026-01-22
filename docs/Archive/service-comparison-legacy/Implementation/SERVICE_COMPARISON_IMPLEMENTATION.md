# Service Comparison Feature - Implementation Guide

## Overview
This document provides a detailed implementation guide for the Azure Service Comparison feature. The feature enables administrators to discover and compare all available Azure services across two regions.

## Quick Start

### Prerequisites
- Azure CLI installed and authenticated (`az login`)
- jq for JSON processing
- Bash 4.0+
- Write permissions in the output directory

### Basic Usage
```bash
# Simple comparison
./services_compare.sh --source-region eastus --target-region westeurope

# With custom output directory
./services_compare.sh --source-region eastus --target-region westeurope --output-dir ./reports

# JSON output only
./services_compare.sh --source-region eastus --target-region westeurope --output-formats json

# Verbose logging
./services_compare.sh --source-region eastus --target-region westeurope --verbose
```

## Architecture Overview

### Component Hierarchy
```
┌─────────────────────────────────────┐
│   services_compare.sh               │ (Main Script)
│   - CLI argument parsing            │
│   - Input validation                │
│   - Output orchestration            │
└────────────┬────────────────────────┘
             │
      ┌──────▼──────────────────────┐
      │ lib/service_comparison.sh   │ (Core Library)
      │ - get_providers_in_region() │
      │ - get_service_families()    │
      │ - get_compute_skus()        │
      │ - get_storage_skus()        │
      │ - compare_services()        │
      │ - compare_skus()            │
      │ - generate_comparison_csv() │
      │ - generate_comparison_json()│
      └──────┬─────────────────────┘
             │
      ┌──────┴──────────────────────────┐
      │   Dependency Libraries          │
      ├─────────────────────────────────┤
      │ lib/utils_log.sh      (Logging) │
      │ lib/utils_cache.sh    (Cache)   │
      │ lib/display.sh        (Output)  │
      │ lib/data_processing.sh(CSV)     │
      └─────────────────────────────────┘
```

### Data Flow Diagram
```
Input: Regions
   │
   ▼
Parse & Validate
   │
   ▼
Initialize Cache
   │
   ├─────────────────────────────┐
   │                             │
   ▼                             ▼
Get Providers              Get Providers
(Source Region)            (Target Region)
   │                             │
   ▼                             ▼
Get Service Families       Get Service Families
   │                             │
   └─────────────────┬───────────┘
                     │
                     ▼
            Compare Services
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
   Compute       Storage      Database
   SKU Query     SKU Query     SKU Query
        │            │            │
        └────────────┼────────────┘
                     │
                     ▼
            Comparative Analysis
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
     CSV Output  JSON Output  Display
                     │
                     ▼
               Write to Files
```

## Module Documentation

### Main Script: `services_compare.sh`

**Purpose**: CLI entry point and orchestration

**Key Functions**:
```bash
usage()                    # Display help message
parse_args()              # Parse command-line arguments
validate_inputs()         # Validate regions and setup
display_summary()         # Show shell-based summary
main()                    # Main execution flow
```

**Usage**:
```bash
./services_compare.sh \
  --source-region eastus \
  --target-region westeurope \
  --output-dir ./reports \
  --output-formats csv,json,display \
  --verbose
```

### Core Library: `lib/service_comparison.sh`

#### Service Discovery Functions

**`get_providers_in_region(region)`**
- **Purpose**: Enumerate all resource providers in a region
- **Input**: Region name (e.g., "eastus")
- **Output**: JSON array of providers with resource types
- **Caching**: 24 hours (configurable via `SC_CACHE_TTL_SERVICES`)
- **API**: `az provider list --expand "resourceTypes/locations"`
- **Example**:
```bash
providers=$(get_providers_in_region "eastus")
echo "$providers" | jq '.[] | .namespace' | head -20
```

**`get_service_families(region)`**
- **Purpose**: Group services by logical family
- **Input**: Region name
- **Output**: JSON object with services grouped by category
- **Categories**: compute, storage, database, fabric, network, containers, analytics
- **Caching**: 24 hours
- **Example**:
```bash
families=$(get_service_families "eastus")
echo "$families" | jq '.compute | length'  # Number of compute services
```

#### SKU Discovery Functions

**`get_compute_skus(region)`**
- **Purpose**: Fetch all Compute SKUs available in a region
- **Input**: Region name
- **Output**: JSON array of compute SKUs (VMs, disks, etc.)
- **Caching**: 24 hours
- **APIs**: 
  - Primary: `az vm list-skus --location <region>`
  - Fallback: Microsoft.Compute/skus REST API
- **Performance**: ~30-60 seconds per region
- **Example**:
```bash
skus=$(get_compute_skus "eastus")
echo "$skus" | jq '.[] | .name' | wc -l  # Count SKUs
```

**`get_storage_skus(region)`**
- **Purpose**: Fetch all Storage SKUs available in a region
- **Input**: Region name
- **Output**: JSON array of storage SKUs
- **Caching**: 24 hours
- **API**: `az storage sku list`
- **Example**:
```bash
skus=$(get_storage_skus "eastus")
echo "$skus" | jq '.[] | .tier' | sort | uniq
```

**`get_database_skus(region)`**
- **Purpose**: Fetch database SKUs and editions
- **Input**: Region name
- **Output**: JSON array of database SKUs
- **Caching**: 24 hours
- **APIs**: `az sql db list-editions`, REST APIs for MySQL/PostgreSQL
- **Example**:
```bash
skus=$(get_database_skus "eastus")
echo "$skus" | jq '.[] | .family' | sort | uniq
```

**`get_fabric_skus(region)`**
- **Purpose**: Fetch Fabric capacity SKUs
- **Input**: Region name
- **Output**: JSON array of Fabric SKUs
- **Caching**: 24 hours
- **API**: Microsoft.Fabric/skus REST API
- **Example**:
```bash
skus=$(get_fabric_skus "eastus")
echo "$skus" | jq '.[] | .name'
```

#### Comparative Analysis Functions

**`compare_services(source_region, target_region)`**
- **Purpose**: Compare service availability between regions
- **Input**: Two region names
- **Output**: JSON object with service comparison
- **Includes**:
  - Service count per region
  - Service-level differences
- **Example**:
```bash
comparison=$(compare_services "eastus" "westeurope")
echo "$comparison" | jq '.serviceCount'
```

**`compare_skus(source_region, target_region, category)`**
- **Purpose**: Compare SKUs for a specific service category
- **Input**: Two regions and category (compute, storage, database, fabric)
- **Output**: JSON object with SKU comparison
- **Includes**:
  - Source SKU count
  - Target SKU count
  - Only in source
  - Only in target
  - Common SKUs
- **Example**:
```bash
cmp=$(compare_skus "eastus" "westeurope" "compute")
echo "$cmp" | jq '{
  source: .sourceCount,
  target: .targetCount,
  gap: (.onlyInSource | length)
}'
```

#### Output Generation Functions

**`generate_comparison_csv(source_region, target_region, output_file)`**
- **Purpose**: Generate CSV report with comparison results
- **Input**: Two regions and output file path
- **Output**: CSV file with rows per service category
- **Format**: ServiceFamily, SourceCount, TargetCount, OnlyInSource, OnlyInTarget, Status
- **Example**:
```bash
generate_comparison_csv "eastus" "westeurope" "./reports/comparison.csv"
cat ./reports/comparison.csv
```

**`generate_comparison_json(source_region, target_region, output_file)`**
- **Purpose**: Generate detailed JSON report
- **Input**: Two regions and output file path
- **Output**: JSON file with hierarchical structure
- **Includes**: Metadata, comparisons per category, detailed SKU lists
- **Example**:
```bash
generate_comparison_json "eastus" "westeurope" "./reports/comparison.json"
jq '.metadata' ./reports/comparison.json
```

## Caching System

### Cache Structure
```
.cache/
├── providers_eastus.json         # Service providers
├── providers_westeurope.json     # Service providers
├── service_families_eastus.json  # Grouped services
├── service_families_westeurope.json
├── compute_skus_eastus.json      # Compute SKUs
├── compute_skus_westeurope.json
├── storage_skus_eastus.json      # Storage SKUs
├── storage_skus_westeurope.json
└── [similar pattern for other categories]
```

### Cache Configuration
```bash
# Set cache TTL (in seconds)
export SC_CACHE_TTL_SERVICES=86400    # 24 hours for service data
export SC_CACHE_TTL_SKUS=86400        # 24 hours for SKU data

# Set cache directory
export CACHE_DIR=/custom/cache/path

# API delays
export SC_API_DELAY_MS=500            # 500ms between API calls
export SC_MAX_RETRIES=3               # 3 retries on failure
```

### Cache Validation
- Automatic TTL-based expiration
- Hash validation for data integrity
- Automatic refresh on cache miss

## Performance Optimization

### API Rate Limiting Handling
```
Azure Service Limits:
- Resource Graph: 10 requests per 10 seconds
- REST APIs: Variable per endpoint
- Retail Prices: 1000 requests per hour

Strategy:
1. Cache aggressively (24h TTL for service metadata)
2. Batch queries when possible
3. Use provider-specific endpoints (faster)
4. Implement exponential backoff (1s, 2s, 4s, 8s)
5. Respect HTTP 429 responses with retry logic
```

### Execution Time Benchmarks
```
Cold Cache (First Run):
├── Service Discovery: ~1-2 minutes
├── SKU Queries (all categories): ~2-3 minutes
├── Analysis & Output: ~30 seconds
└── Total: ~4-5 minutes

Warm Cache (Subsequent Runs):
└── Total: ~30-45 seconds
```

### Memory Usage
- Typical memory: 50-100 MB for full comparison
- Large SKU sets (Compute): ~20-30 MB

## Troubleshooting

### Common Issues

**Issue: Authentication Error**
```
Error: No subscriptions found. Make sure you have an active subscription.

Solution: Run 'az login' and ensure account has access to target subscriptions
```

**Issue: API Throttling (429 errors)**
```
Error: The request rate limit has been exceeded

Solution: 
- Feature automatically retries with exponential backoff
- If persistent, increase SC_API_DELAY_MS to 1000
- Reduce number of concurrent queries
```

**Issue: Invalid Region**
```
Error: Invalid source region: invalid-region

Solution: Use valid Azure region names (az account list-locations)
```

**Issue: Cache Corruption**
```
Error: Cache validation failed for compute_skus_eastus

Solution:
- Delete .cache directory
- Feature will rebuild cache on next run
```

**Issue: Insufficient Permissions**
```
Warning: Insufficient permissions to query fabric SKUs

Solution:
- Grant reader role on subscription
- Or use --output-formats csv,display (skips unavailable categories)
```

### Debug Logging
```bash
# Enable verbose output
./services_compare.sh --source-region eastus --target-region westeurope --verbose

# View logs
tail -f services_comparison.log
```

## Integration Examples

### Bash Script Integration
```bash
# Compare regions and extract summary
./services_compare.sh --source-region eastus --target-region westeurope

# Parse CSV output
awk -F',' '$NF ~ /PARTIAL_MATCH/ {print $1, $5}' output/services_comparison.csv

# Extract specific gaps
jq '.comparisons.compute.onlyInSource' output/services_comparison.json
```

### Scheduled Comparisons
```bash
# Cron job for weekly comparisons
0 2 * * 0 cd /path/to/repo && \
  ./services_compare.sh \
    --source-region eastus \
    --target-region westeurope \
    --output-dir ./weekly_reports/$(date +\%Y\%m\%d)
```

## Testing

### Unit Testing
```bash
# Run tests
cd tests
./test_services_compare.sh

# Output sample
PASS: test_get_providers_in_region
PASS: test_get_service_families
PASS: test_get_compute_skus
...
```

### Integration Testing
```bash
# Real API calls test
./test_services_e2e.sh --source-region eastus --target-region westeurope
```

## Maintenance

### Regular Maintenance Tasks
1. **Daily**: Monitor cache hits (> 80% expected)
2. **Weekly**: Review error logs for API failures
3. **Monthly**: Validate cache data integrity
4. **Quarterly**: Review and update service category lists

### Cache Cleanup
```bash
# Clear all cache
rm -rf .cache

# Clear specific region
rm .cache/*_eastus.json

# Clear old cache (>30 days)
find .cache -type f -mtime +30 -delete
```

## Future Enhancements

### Planned Features
- [ ] Pricing comparison integration
- [ ] SLA comparison
- [ ] Feature availability matrix
- [ ] Real-time availability monitoring
- [ ] Web dashboard visualization
- [ ] Email report generation
- [ ] Slack integration

### Extension Points
- Service category plugins
- Custom output formats
- Integration with third-party tools
