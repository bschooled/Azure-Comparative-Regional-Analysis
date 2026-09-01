# Curated Service Catalog

The curated service catalog adds stable service identity, provider/resource-type
bindings, migration-relevant capabilities, availability-zone guidance, pricing
search hints, evidence, and selected regional exceptions to live Azure discovery.

The canonical editable source is:

```text
data/feature_catalog/services.json
```

It currently describes 64 service views across 13 families. It is deliberately
not a copy of every Azure provider, resource type, SKU, price, quota, or region.
Those volatile facts are discovered from Azure APIs at run time.

## What is curated and what is discovered

| Curated in `services.json` | Discovered dynamically |
|---|---|
| Stable `service_key`, display name, family, aliases | Providers registered and exposed in the active Azure cloud/subscription |
| Provider/resource-type bindings and disambiguation hints | Resource types and provider locations returned by ARM |
| Canonical service identity and Retail Prices search hints | SKU names, restrictions, locations, and effective availability |
| Capability labels, importance, default posture, operator notes | Region availability-zone metadata |
| General zone-support posture and selected regional exceptions | Inventory, quotas, current prices, and comparison status |
| Evidence links and verification dates | Subscription-specific restrictions and service maturity |

Catalog statements are planning metadata, not deployment guarantees. Always
confirm a target design against current provider, SKU, quota, pricing, and region
results.

## Source schema

The file is JSON with this top-level shape:

```json
{
  "version": 1,
  "generated_from": "canonical",
  "services": []
}
```

### Service object

| Field | Required by current builders | Meaning |
|---|---:|---|
| `service_key` | Yes | Stable, unique catalog key; use lowercase kebab-case. |
| `display_name` | Yes | User-facing Azure service or service-view name. |
| `family` | Yes | Stable grouping such as `compute`, `databases`, or `networking`. |
| `summary` | No | Short migration-oriented description. |
| `aliases` | No | Search and identity aliases. Generated identity output prepends the display name and its non-`Azure` form. |
| `providers` | No | One or more provider bindings. The canonical source includes it for every service; an empty or missing array cannot match live output. |
| `zone_support` | No | Default zone posture and notes. Missing values become `unknown` in generated artifacts. |
| `capabilities` | No | Curated capability records. The canonical source includes the array, which may be empty. |
| `evidence` | No | Supporting references and verification dates. |
| `regional_overrides` | No | Region notes and capability/zone exceptions keyed by normalized Azure region name. |
| `pricing` | No | Canonical Retail Prices identity/search hints. |

Representative service:

```json
{
  "service_key": "azure-postgresql-flexible-server",
  "display_name": "Azure Database for PostgreSQL",
  "family": "databases",
  "aliases": ["postgres", "postgresql"],
  "providers": [{
    "namespace": "microsoft.dbforpostgresql",
    "resource_types": ["flexibleservers"]
  }],
  "zone_support": {
    "default": "both",
    "notes": "Deployment options depend on region and tier."
  },
  "capabilities": [],
  "evidence": []
}
```

Provider namespaces and resource types are matched case-insensitively by the
consumers. The source convention is lowercase.

### Provider binding

```json
{
  "namespace": "microsoft.web",
  "resource_types": ["sites", "serverfarms"],
  "match_hints": {
    "resource_type_contains": ["serverfarms"],
    "sku_name_contains": ["p1", "s1"],
    "prefer_when_skus": true,
    "prefer_when_no_skus": false,
    "shared_provider_fallback": false
  }
}
```

`match_hints` disambiguate services sharing a namespace. Matching awards the
largest weight to exact resource types, followed by contained resource-type
tokens, SKU-name tokens, and the boolean preferences. If no candidate scores,
the Python CLI uses the first catalog service bound to that namespace. Keep
bindings specific and ordered intentionally.

### Capability and regional override

```json
{
  "key": "zone_redundant_ha",
  "label": "Zone-redundant high availability",
  "category": "resiliency",
  "importance": "high",
  "notes": "Region and tier specific.",
  "availability": {
    "default": "available",
    "regions": {}
  },
  "requires_zone_support": true
}
```

```json
{
  "regional_overrides": {
    "swedencentral": {
      "notes": "Validate the target design directly in-region.",
      "capabilities": {
        "zone_redundant_ha": {
          "status": "unknown",
          "notes": "Confirm support before committing the design."
        }
      }
    }
  }
}
```

Current source values use:

- zone modes: `regional`, `zonal`, `zone-redundant`, `both`, `unknown`
- capability status: `available`, `unavailable`, `unknown`
- importance: `high`, `medium`

At run time, consumers can also emit `not-applicable`, `service-unavailable`,
`region-without-zones`, and `zone-support-unverified`. A capability marked
`requires_zone_support` becomes `not-applicable` when live region metadata says
the region has no availability zones.

### Evidence

```json
{
  "source_type": "microsoft-learn",
  "source_url": "https://learn.microsoft.com/azure/...",
  "last_verified": "2026-04-13",
  "notes": "Zone-support reference."
}
```

Use ISO `YYYY-MM-DD` dates. Evidence records provenance; they do not replace
live validation.

### Pricing identity

```json
{
  "pricing": {
    "serviceNames": ["Virtual Machines"],
    "serviceFamilies": ["Compute"],
    "productNames": ["Virtual Machines"],
    "filters": [{
      "service_name": "Virtual Machines",
      "price_type": "Consumption"
    }]
  }
}
```

The source currently uses pricing profiles only where Retail Prices naming needs
stable guidance. `filters` support `service_name`, `service_family`,
`product_name_contains`, and `price_type`. Hosted pricing resolution also
understands `query_mode` (`first-match` or `merge`).

## Canonical identity mapping

`build-catalog` produces a canonical identity record for every service:

```json
{
  "serviceKey": "azure-storage",
  "canonicalServiceId": "azure-storage",
  "canonicalServiceName": "Azure Storage",
  "canonicalFamilyKey": "storage",
  "providerNamespaces": ["microsoft.storage"],
  "resourceTypes": ["storageaccounts"],
  "aliases": ["Azure Storage", "Storage"],
  "pricingServiceNames": ["Storage"]
}
```

The generated mapping:

1. uses `display_name` as the first canonical name;
2. slugifies that name to lowercase kebab-case for `canonicalServiceId`;
3. lowercases `family` for `canonicalFamilyKey`;
4. normalizes and deduplicates aliases, provider namespaces, resource types, and
   pricing names;
5. builds `providerIndex` and `familyIndex` lookup maps.

Provider bindings are not necessarily one-to-one. For example, multiple
Microsoft.Web and Microsoft.Network service views require resource-type and
matching-hint disambiguation.

Comparison rows without a curated hosted match receive a derived fallback
identity plus diagnostics. Generate a curation backlog from such rows with:

```bash
PYTHONPATH=src python3 -m azure_compare_cli build-identity-gap-report \
  --input output/<comparison>.json \
  --output data/generated/canonical_identity_gaps.snapshot.json
```

## Build and validation

Bootstrap the editable Python CLI once:

```bash
./scripts/bootstrap_python.sh
```

Build all primary artifacts:

```bash
.venv/bin/python -m azure_compare_cli build-catalog \
  --source data/feature_catalog/services.json \
  --output-json data/generated/feature_catalog.snapshot.json \
  --output-sqlite data/generated/feature_catalog.db \
  --output-identity-json data/generated/canonical_service_identity.snapshot.json
```

Without the virtual environment:

```bash
PYTHONPATH=src python3 -m azure_compare_cli build-catalog \
  --source data/feature_catalog/services.json \
  --output-json data/generated/feature_catalog.snapshot.json \
  --output-sqlite data/generated/feature_catalog.db \
  --output-identity-json data/generated/canonical_service_identity.snapshot.json
```

There is currently no separate JSON Schema validator. A successful build checks
JSON parsing, required fields used by the builder, duplicate SQLite primary
keys, and artifact serialization. Add these lightweight source checks before
review:

```bash
jq empty data/feature_catalog/services.json

jq -e '
  .version == 1
  and (.services | type == "array" and length > 0)
  and all(.services[];
    (.service_key | type == "string" and length > 0)
    and (.display_name | type == "string" and length > 0)
    and (.family | type == "string" and length > 0)
    and (.providers | type == "array")
    and (.capabilities | type == "array"))
' data/feature_catalog/services.json >/dev/null

test -z "$(jq -r '.services[].service_key' data/feature_catalog/services.json |
  sort | uniq -d)"
```

`./tests/quick_validation.sh` also calls the automatic artifact builder, but the
full script performs live Azure provider/SKU checks and therefore needs Azure
CLI access.

## Generated artifacts

`data/generated/` is ignored by Git. Rebuild it locally or during packaging; do
not edit or commit its contents.

| Artifact | Contents and use |
|---|---|
| `feature_catalog.snapshot.json` | Full source document plus a lowercase `provider_index`; used by shell/Python enrichment. |
| `feature_catalog.db` | Query-friendly SQLite projection with `services`, `provider_bindings`, `capabilities`, and `evidence` tables. |
| `canonical_service_identity.snapshot.json` | Normalized identities plus provider and family indexes. |
| `canonical_identity_gaps.snapshot.json` | Optional report generated from comparison rows that used fallback identity. |

The SQLite projection intentionally does not contain aliases, pricing profiles,
regional overrides, or matching hints. Use the JSON snapshot when those fields
are required.

Example SQLite inspection without the `sqlite3` executable:

```bash
python3 - <<'PY'
import sqlite3

db = sqlite3.connect("data/generated/feature_catalog.db")
for table in ("services", "provider_bindings", "capabilities", "evidence"):
    count = db.execute(f"SELECT COUNT(*) FROM {table}").fetchone()[0]
    print(f"{table}: {count}")
db.close()
PY
```

## Consumer behavior

### Standalone shell workflows

- `lib/service_comparison.sh` reads the editable source directly to build the
  default deployable provider scope and allowed resource types. A small
  supplemental provider list in `lib/service_catalog.sh` extends that scope.
- `lib/python_cli.sh` rebuilds generated artifacts when the source is newer than
  any primary artifact.
- `services_compare.sh` and inventory comparison output are enriched in place
  from `feature_catalog.snapshot.json`. Enrichment adds the matched service,
  capabilities, evidence, regional notes, and zone posture.
- The Rich renderer uses the enriched comparison JSON. Shell formatting remains
  available as a fallback.

Live provider/SKU data determines whether a service is present. The catalog
annotates that result; it does not manufacture availability.

### Hosted pipeline and web app

The hosted path currently has two related catalog flows:

1. The Function App comparison engine imports the embedded
   `azure_pipeline/function_app/shared/curated_catalog.py`. It uses provider and
   resource-type matching to attach curated regional details, canonical
   identity, pricing identity, fallback diagnostics, and capability rows to
   comparison results.
2. Web packaging builds and copies the generated JSON/SQLite artifacts into the
   App Service package. `web_app/server.js` reports their presence, size, and
   modification time in `/api/session` application context.

The Function App does **not** load `data/generated/feature_catalog.snapshot.json`
or the SQLite database at run time. The embedded Python catalog is therefore a
second representation that must be reviewed alongside `services.json` for a
hosted behavior change. Service keys and some resource-type coverage currently
differ between the two representations; do not assume artifact regeneration
updates Function App matching.

## Contribution and update workflow

1. Confirm the change is stable planning metadata rather than a volatile fact
   already available from Azure APIs.
2. Find the existing service by `service_key`, provider namespace, and resource
   type. Extend it instead of creating an overlapping service unless a shared
   provider genuinely needs a distinct service view.
3. Add concise operator-facing notes. Avoid promises that a SKU or capability is
   universally deployable.
4. Add or refresh Microsoft evidence and `last_verified`.
5. Use a regional override only for a meaningful, evidenced exception. Prefer
   `unknown` plus validation guidance when certainty is incomplete.
6. If canonical pricing names are needed, add the narrowest useful pricing
   profile.
7. For hosted behavior, make the equivalent documentation/catalog-data update
   in `azure_pipeline/function_app/shared/curated_catalog.py`; do not expect the
   generated snapshot to be loaded by the Function App.
8. Run the source checks and `build-catalog` command above.
9. Inspect the generated identity for the changed service and query the SQLite
   row counts or records.
10. When comparison output is available, run `build-identity-gap-report` and
    confirm the intended fallback count decreases without unrelated identity
    changes.

Generated files should remain untracked.

## Troubleshooting

### A service is not matched

- Normalize the namespace and resource type to lowercase.
- Confirm the binding appears in the relevant consumer: `services.json` for
  shell enrichment, embedded `curated_catalog.py` for hosted comparisons.
- For a shared namespace, add an exact resource type before relying on
  `resource_type_contains` or SKU-name hints.
- Inspect `canonical_identity_gaps.snapshot.json` for
  `missing-curated-binding` and observed-resource-type diagnostics.

### The wrong service wins for a shared provider

Review all services bound to that namespace. Exact resource-type matches score
highest; ambiguous zero-score matches fall back to catalog order. Tighten
bindings and hints rather than changing a display name.

### Zone support looks too confident or unavailable

Catalog zone posture is combined with live region metadata. An unknown live
zone result intentionally downgrades zonal defaults to
`zone-support-unverified`; a no-zone region produces `region-without-zones`.
Check Azure location discovery and cache freshness before changing curated
defaults.

### Artifacts are stale or missing

Delete only the ignored files under `data/generated/` and rerun `build-catalog`.
Shell helpers also rebuild when `services.json` is newer. Web packages must be
rebuilt to carry refreshed artifacts.

### The JSON snapshot and SQLite database disagree

Rebuild both in one `build-catalog` invocation. Remember that the SQLite
database is a reduced projection and intentionally omits several JSON fields.

### Shell output changed but hosted output did not

This indicates drift between `services.json` and the Function App's embedded
catalog. Regenerating artifacts is insufficient; compare the binding, identity,
capability, and regional metadata in both representations.
