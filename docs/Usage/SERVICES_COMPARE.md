# Region-to-Region Service + SKU Comparison (`services_compare.sh`)

This guide covers the **region-only** comparison workflow:

- It does **not** require an inventory (no ARG query).
- It compares what Azure says is available in each region, per provider.
- Outputs are **JSON-first**; the CSV is derived from the JSON and is **SKU-granular** (one row per provider per SKU).

## Quick Start

```bash
# Compare two regions
./services_compare.sh --source-region westus2 --target-region swedencentral

# Write results into ./output
./services_compare.sh --source-region westus2 --target-region swedencentral --output-dir output

# JSON only
./services_compare.sh --source-region westus2 --target-region swedencentral --output-formats json
```

### Placeholder: terminal output

Paste an example run summary here:

```text
# (paste output here)
```

## Output Files

`services_compare.sh` produces a pair of files named like:

- `<source>_vs_<target>_providers.json`
- `<source>_vs_<target>_providers.csv`

Example:

- `output/westus2_vs_swedencentral_providers.json`
- `output/westus2_vs_swedencentral_providers.csv`

### CSV schema (SKU-granular)

Each row represents one provider+SKU in the comparison.

```csv
Provider,SKU,ResourceType,SourceHasSKU,TargetHasSKU,SourceSKUCount,TargetSKUCount,SourceResourceTypes,TargetResourceTypes,Status
```

### Placeholder: CSV excerpt

```csv
# (paste 10-20 representative rows here)
```

### JSON schema (source of truth)

The JSON contains one record per provider (including provider-specific “synthetic” entries noted below). Each provider contains `sourceRegion`/`targetRegion` objects with `skus[]` arrays.

### Placeholder: JSON excerpt

```json
{
  "provider": "(paste provider name here)",
  "status": "(FULL_MATCH|PARTIAL_MATCH|...)",
  "sourceRegion": {
    "name": "(region)",
    "resourceTypes": 0,
    "skuCount": 0,
    "skus": []
  },
  "targetRegion": {
    "name": "(region)",
    "resourceTypes": 0,
    "skuCount": 0,
    "skus": []
  }
}
```

## Notable SKU Breakouts

Some providers do not expose useful `/skus` data (or have data that needs specialized handling). For these, the tool uses provider-specific backends to produce consistent SKU rows.

### Managed disks (`Microsoft.Compute/disks`)

Managed disks are emitted as a **synthetic provider entry**:

- Provider: `Microsoft.Compute/disks`
- SKU objects are **name-only** (deduped by `.name`)

Example query (find disk SKUs for the pair):

```bash
jq -r '.[] | select(.provider=="Microsoft.Compute/disks") | .sourceRegion.skus[].name' \
  output/westus2_vs_swedencentral_providers.json
```

## Tips

- Use `--cache-dir` to persist results between runs.
- If you’re comparing many region pairs, run once per pair and keep the JSON artifacts; regenerate CSV later if needed.
