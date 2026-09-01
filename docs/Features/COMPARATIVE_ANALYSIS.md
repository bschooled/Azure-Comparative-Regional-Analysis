# Comparative Regional Analysis Feature

## Overview

The Comparative Regional Analysis feature generates cross-region availability tables that show, for each service type and SKU found in the source region, whether it's available in the target region.

## New Output Files

### 1. `service_availability_comparison.csv`
A CSV table with the following format:

```csv
ServiceType,SKU/Name,eastusAvailable,eastusDetails,westeuropeAvailable,westeuropeDetails
Microsoft.Compute/virtualMachines,"Standard_D2s_v5",YES,Found in inventory,true,Available
Microsoft.Compute/virtualMachines,"Standard_D4s_v5",YES,Found in inventory,true,Available
Microsoft.Storage/storageAccounts,"Standard_LRS",YES,Found in inventory,true,Available
Microsoft.Storage/storageAccounts,"Premium_LRS",YES,Found in inventory,false,"Not available in target region"
```

**Columns:**
- `ServiceType`: Azure resource type (e.g., `Microsoft.Compute/virtualMachines`)
- `SKU/Name`: Resource SKU or name (e.g., VM size, storage tier)
- `{SourceRegion}Available`: Boolean showing if resource exists in source region
- `{SourceRegion}Details`: Details about source region status
- `{TargetRegion}Available`: Boolean showing if SKU is available in target region
- `{TargetRegion}Details`: Details about target region status or restrictions

**Use Cases:**
- Quick reference for migration feasibility
- Identify resources that need alternative SKUs in target region
- Spot incompatibilities before migration

### 2. `service_availability_comparison.json`
A structured JSON file with rich metadata:

```json
[
  {
    "serviceType": "Microsoft.Compute/virtualMachines",
    "inventoryCount": 42,
    "availability": [
      {
        "region": "eastus",
        "available": true,
        "resourceCount": 42,
        "evidence": "Found in source region inventory"
      },
      {
        "region": "westeurope",
        "available": true,
        "details": [
          {
            "armSkuName": "Standard_D2s_v5",
            "available": true,
            "restrictions": []
          },
          {
            "armSkuName": "Standard_D4s_v5",
            "available": true,
            "restrictions": []
          }
        ]
      }
    ]
  }
]
```

**Use Cases:**
- Programmatic analysis and automation
- Building migration decision engines
- Integration with other tools

### 3. `availability_summary.txt`
Human-readable summary with statistics:

```
================================================================================
AZURE REGIONAL AVAILABILITY COMPARISON
================================================================================

Source Region: eastus
Target Region: westeurope
Report Generated: 2026-01-20 10:30:45 UTC

================================================================================
INVENTORY SUMMARY
================================================================================
Total Resources in Source Region: 156

Resources by Type:
  Microsoft.Compute/virtualMachines: 42
  Microsoft.Storage/storageAccounts: 28
  Microsoft.Network/networkInterfaces: 31
  Microsoft.Network/publicIPAddresses: 12
  Microsoft.Compute/disks: 43

================================================================================
AVAILABILITY IN TARGET REGION
================================================================================
Total Service Types Checked: 5
Available in Target Region:  5
Unavailable in Target Region: 0

================================================================================
RESTRICTIONS AND NOTES
================================================================================
Services with Restrictions in Target Region: 1
  Microsoft.Compute/virtualMachines (Standard_D8s_v5): NotAvailableForSubscription, Zone limitations
```

**Use Cases:**
- Executive reporting
- Quick validation before migration planning
- Documentation of cross-region support

## How It Works

### Data Collection Phase
1. Gathers all unique service types from the source region inventory
2. For each service type, extracts all unique SKUs/names

### Comparison Phase
For each service type and SKU:
1. **Source Region Check**: Confirms the resource exists in inventory
2. **Target Region Check**: Uses availability data to determine if SKU is available
3. **Restriction Check**: Identifies any limitations or conditions

### Output Generation
Creates three complementary views:
- **CSV**: Easy to import into spreadsheets or analysis tools
- **JSON**: Machine-readable for automation
- **Text**: Human-readable summary for reports

## Integration with Pipeline

The comparative analysis runs automatically after availability checking:

```
Phase 1: Resource Inventory (ARG)
   ↓
Phase 2: Inventory Summarization
   ↓
Phase 3: Pricing Enrichment
   ↓
Phase 4: Availability Checking
   ↓
Phase 5: Comparative Analysis ← NEW
```

## Usage Examples

### Analyzing VM Availability
```bash
# View all VMs and their cross-region status
grep "Microsoft.Compute/virtualMachines" output/service_availability_comparison.csv
```

### Finding Unavailable Resources
```bash
# Find resources not available in target region
jq '.[] | select(.available == false)' output/service_availability_comparison.json
```

### Counting Migration-Ready Services
```bash
# Count services available in both regions
jq '[.[] | select(.availability[].available == true)] | length' \
  output/service_availability_comparison.json
```

### Generating Reports
```bash
# View summary
cat output/availability_summary.txt

# Extract specific service type
jq '.[] | select(.serviceType == "Microsoft.Storage/storageAccounts")' \
  output/service_availability_comparison.json
```

## Key Benefits

1. **Migration Planning**: Clear view of what needs to be migrated and where
2. **Risk Assessment**: Identify unavailable SKUs early
3. **Cost Analysis**: Compare pricing across regions for available services
4. **Compliance**: Verify service availability meets requirements
5. **Documentation**: Comprehensive audit trail for compliance/governance

## Limitations

- Comparison is service-type level, not individual resource level
- SKU availability is based on region availability checks
- Restrictions information depends on Azure API completeness
- Some specialized services may not be fully captured
