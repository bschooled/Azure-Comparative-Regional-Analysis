# Shell Display Feature

## Overview

A new shell display module has been added that prints a comprehensive execution summary directly to the terminal. The summary includes:

- **Inventory Statistics**: Resource counts by type
- **Pricing Information**: Number of priced and unpriced resources
- **Availability Status**: Service availability in target region
- **Comparative Analysis**: Cross-region service comparison
- **Execution Statistics**: API calls, cache hits, errors/warnings
- **Output Files List**: All generated output files
- **Final Status**: Success/warning indicator

## Features

### No External Dependencies
The display module uses only:
- Standard bash utilities (printf, awk, sed, grep, etc.)
- jq (already required by the project)
- Native shell formatting and arithmetic

### Rich Console Output
Formatted display with:
- Colored text (using existing color codes)
- Box drawing characters (├─╠─╣─╚╝═║)
- Icons and symbols (✓ ✗ ⚠ ℹ)
- Organized sections
- Clear visual hierarchy

### Real-time Information
Displays:
- Actual resource counts from inventory
- Pricing meter mappings status
- Service availability breakdown
- Migration blockers (unavailable services)
- API performance metrics
- Error and warning counts

## Example Output

```
╔══════════════════════════════════════════════════════════════════════════╗
║ INVENTORY SUMMARY                                                        ║
╠══════════════════════════════════════════════════════════════════════════╣
  Total Resources:                 156
  
  Resource Types:
    Microsoft.Compute/virtualMachines: 42
    Microsoft.Storage/storageAccounts: 28
    Microsoft.Network/networkInterfaces: 31
╚══════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════╗
║ AVAILABILITY IN TARGET REGION: westeurope                               ║
╠══════════════════════════════════════════════════════════════════════════╣
  Service Types Checked:           5
  Available in Target:             5
  
  ✓  All service types available in target region
╚══════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════╗
║ COMPARATIVE REGIONAL ANALYSIS                                            ║
╠══════════════════════════════════════════════════════════════════════════╣
  Service Types Analyzed:          5
  ✓  5 services available in both regions
  Total Resources in Source:       156
╚══════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════╗
║ EXECUTION STATISTICS                                                     ║
╠══════════════════════════════════════════════════════════════════════════╣
  Source Region:                   eastus
  Target Region:                   westeurope
  Scope:                           all
  Parallel Concurrency:            8
  
  API Activity:
    API Calls Made:                24
    Cache Hits:                    8
    Cache Hit Rate:                25%
  
  Execution Errors:                0
  Execution Warnings:              2
╚══════════════════════════════════════════════════════════════════════════╝

╔══════════════════════════════════════════════════════════════════════════╗
║ OUTPUT FILES GENERATED                                                   ║
╠══════════════════════════════════════════════════════════════════════════╣
  ✓ output/source_inventory.json
  ✓ output/source_inventory_summary.csv
  ✓ output/price_lookup.csv
  ✓ output/target_region_availability.json
  ✓ output/service_availability_comparison.csv
  ✓ output/service_availability_comparison.json
  ✓ output/availability_summary.txt
  ✓ output/run.log
╚══════════════════════════════════════════════════════════════════════════╝

╔════════════════════════════════════════════════════════════════════════════╗
║                                                                            ║
║  ✅ EXECUTION COMPLETED SUCCESSFULLY                                        ║
║                                                                            ║
╚════════════════════════════════════════════════════════════════════════════╝
```

## Functions

### Display Functions

#### `print_box(title)`
Prints a formatted box header with title
```bash
print_box "MY SECTION TITLE"
```

#### `print_box_end()`
Prints the box footer

#### `print_divider()`
Prints a horizontal divider line

#### `print_kv(key, value, [color])`
Prints a key-value pair with optional color
```bash
print_kv "Total Resources" "156" "${GREEN}"
```

#### `print_success_item(text)`
Prints a success item with green checkmark
```bash
print_success_item "All services available"
```

#### `print_warning_item(text)`
Prints a warning item with yellow warning symbol
```bash
print_warning_item "Some resources unpriced"
```

#### `print_error_item(text)`
Prints an error item with red X mark
```bash
print_error_item "Service not available"
```

#### `print_info_item(text)`
Prints an info item with blue info symbol
```bash
print_info_item "Additional information"
```

### Summary Display Functions

#### `display_inventory_summary()`
Shows resource counts by type

#### `display_pricing_summary()`
Shows pricing enrichment statistics

#### `display_availability_summary()`
Shows target region availability status

#### `display_comparative_summary_shell()`
Shows cross-region comparison results

#### `display_execution_stats()`
Shows API activity and execution metrics

#### `display_complete_summary()`
Shows complete end-to-end execution summary

## Usage

The shell display runs automatically at the end of script execution:

```bash
./inv.sh --all --source-region eastus --target-region westeurope
```

The summary is printed after all processing completes and files are generated.

## Colors Used

- **Green (${GREEN})**: Success items, available services
- **Red (${RED})**: Errors, unavailable services
- **Yellow (${YELLOW})**: Warnings, restricted services
- **Blue (${BLUE})**: Information, section headers

## Benefits

✓ **Immediate Feedback**: See results instantly in terminal
✓ **No External Tools**: Uses only bash and standard utilities
✓ **Visual Clarity**: Color-coded and well-organized output
✓ **Comprehensive**: Shows inventory, pricing, availability, and stats
✓ **Performance Metrics**: Displays API call counts and cache hit rates
✓ **Migration Support**: Highlights unavailable services for planning

## Integration

The display module integrates seamlessly with the existing pipeline:
- Uses variables set by other modules
- Reads generated output files
- No performance overhead
- Runs only at script completion

## Customization

To customize the display, edit `lib/display.sh`:
- Modify box drawing characters
- Change colors
- Add/remove sections
- Adjust output formatting

## File Statistics

Uses data from:
- `source_inventory.json` - Resource inventory
- `price_lookup.csv` - Pricing data
- `target_region_availability.json` - Availability status
- `service_availability_comparison.json` - Comparative analysis

No additional API calls or processing required.
