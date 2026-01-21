# Comparative Analysis Feature - Implementation Summary

## What's New

A new **Phase 5: Comparative Regional Analysis** has been added to the execution pipeline. This phase generates cross-region availability comparison tables for all services discovered in the source region.

## Files Added

### Code
- **`lib/comparative_analysis.sh`**: Core module implementing comparative analysis
  - `generate_comparative_tables()`: Main function coordinating comparison
  - `generate_comparative_csv()`: Generates CSV comparison table
  - `generate_comparative_json()`: Generates JSON comparison with rich metadata
  - `generate_availability_summary()`: Creates human-readable summary
  - `display_comparative_summary()`: Console output summary

### Documentation
- **`COMPARATIVE_ANALYSIS.md`**: Detailed feature documentation
  - Architecture and how it works
  - Output file formats with examples
  - Usage examples and best practices
  - Limitations and considerations

## Files Modified

### Core Script
- **`inv.sh`**: Updated to include Phase 5 and new module import
  - Added source for `comparative_analysis.sh`
  - Added Phase 5 execution block
  - Updated final summary to call comparative analysis display

### Documentation
- **`README_USAGE.md`**: Updated to document new output files and outputs
- **`QUICKSTART.md`**: Added comparative analysis in output review section
- **`STATUS.md`**: Updated with new feature and module information

## New Outputs Generated

### CSV Format: `service_availability_comparison.csv`
Quick reference table showing:
- Service type and SKU
- Availability in source region (from inventory)
- Availability in target region
- Status and details for each region

**Perfect for:**
- Spreadsheet analysis
- Executive reporting
- Quick reference

### JSON Format: `service_availability_comparison.json`
Structured data with rich metadata:
- Service type
- Resource counts
- Regional availability details
- Restrictions and limitations
- Evidence for each determination

**Perfect for:**
- Programmatic analysis
- Tool integration
- Automation workflows

### Text Format: `availability_summary.txt`
Human-readable report with:
- Inventory statistics by type
- Availability counts and percentages
- List of unavailable services
- Restrictions and caveats

**Perfect for:**
- Human review
- Documentation
- Executive dashboards

## Execution Flow

The complete execution now follows this sequence:

```
1. Initialize & Validate
2. Phase 1: Resource Inventory (ARG)
   └─ Collect all resources from source region
3. Phase 2: Inventory Summarization
   └─ Summarize by type and SKU
4. Phase 3: Pricing Enrichment
   └─ Map to pricing meters
5. Phase 4: Availability Checking
   └─ Check SKU availability in target region
6. Phase 5: Comparative Analysis ← NEW
   └─ Generate cross-region comparison tables
7. Summary and Exit
   └─ Display results and comparative summary
```

## Key Features

✅ **Automatic Execution**: Runs as part of the standard pipeline  
✅ **Multiple Formats**: CSV, JSON, and text outputs  
✅ **Rich Metadata**: Includes counts, restrictions, and evidence  
✅ **Performance**: Efficient aggregation and table generation  
✅ **Integrated**: Works seamlessly with existing phases  
✅ **Scalable**: Handles large inventories efficiently  

## Usage

No changes needed to existing usage. Simply run the script as before:

```bash
./inv.sh --all \
  --source-region eastus \
  --target-region westeurope
```

Comparative tables will be automatically generated in the output directory:
- `output/service_availability_comparison.csv`
- `output/service_availability_comparison.json`
- `output/availability_summary.txt`

## Example Outputs

### CSV Example
```
ServiceType,SKU/Name,eastusAvailable,eastusDetails,westeuropeAvailable,westeuropeDetails
Microsoft.Compute/virtualMachines,"Standard_D2s_v5",YES,Found in inventory,true,Available
Microsoft.Storage/storageAccounts,"Standard_LRS",YES,Found in inventory,true,Available
```

### JSON Example
```json
{
  "serviceType": "Microsoft.Compute/virtualMachines",
  "inventoryCount": 42,
  "availability": [
    {
      "region": "eastus",
      "available": true,
      "resourceCount": 42
    }
  ]
}
```

## Next Steps

You can now:
1. Review comparative tables to understand cross-region compatibility
2. Identify services that need SKU adjustments for target region
3. Use tables for migration planning and documentation
4. Extract data for cost comparison across regions
5. Generate compliance reports for governance

## Technical Details

The feature works by:
1. Extracting unique service types from inventory
2. For each type, gathering unique SKUs
3. Checking source region inventory (where resources exist)
4. Querying availability data from Phase 4 (target region)
5. Aggregating and formatting into three output formats
6. Generating statistics and summary information

All operations are efficient and leverage cached availability data from Phase 4.
