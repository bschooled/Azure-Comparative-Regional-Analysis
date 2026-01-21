
# Spec: Bash script to inventory Azure resources (by region), map to pricing meters, and check availability in a target region

**Author**: Copilot for <Prin Sol Engineer>  
**Purpose**: Produce a fast, reliable automation using Azure CLI and/or Azure REST APIs to
1) enumerate resources in a source region with quantities,  
2) enrich them with **Service Name**, **Service Family**, and **Meter Name** (pricing meters), and  
3) determine if equivalent resource types/SKUs are available in a target region.

---

## 1) Scope & outputs

### Inputs (CLI flags)
- `--source-region <region>` (e.g., `eastus`) **required**
- `--target-region <region>` (e.g., `westeurope`) **required**
- **Scope selector** (mutually exclusive):
  - `--all` (all accessible subscriptions in tenant)
  - `--mg <managementGroupId>`
  - `--rg <subId>:<resourceGroupName>`
- Optional filters:
  - `--subscriptions <subId1,subId2,...>` (overrides `--all`)
  - `--resource-types <csv list>` (e.g., `Microsoft.Compute/virtualMachines,Microsoft.Compute/disks`)
- Performance switches:
  - `--parallel <n>` (concurrency for REST calls; default 8)
  - `--cache-dir <path>` (persist pricing pages & SKU lists)

### Outputs (files)
- `source_inventory.json` — raw ARG output for resources in source region (scoped)  
- `source_inventory_summary.csv` — *quantities* summarized by `type`, `sku`, and service-specific fields (e.g., VM size, disk tier)  
- `price_lookup.csv` — unique resource tuples mapped to **serviceName**, **serviceFamily**, **meterName**, **armSkuName**, **armRegionName**, **unitOfMeasure**, **retailPrice**  
- `target_region_availability.json` — availability verdict per resource type/SKU in target region with any **restrictions** or notes  
- `run.log` — timing, API paging, and error summaries

---

## 2) Design choices (fast & accurate)

1) **Discovery at scale** with **Azure Resource Graph (ARG)** via `az graph query`, scoped to **All/MG/RG** and filtered by `location == source-region`. ARG is optimized for large fleets and cross-subscription queries. [1](https://learn.microsoft.com/en-us/cli/azure/graph?view=azure-cli-latest)[2](https://learn.microsoft.com/en-us/azure/governance/resource-graph/samples/starter)  
2) **Pricing meter enrichment** with **Azure Retail Prices API** (`prices.azure.com`) using narrow OData filters on `serviceName`, `armRegionName`, `armSkuName` to retrieve **serviceName / serviceFamily / meterName**. Handle pagination via `NextPageLink`/`$skip`. **No auth required**. [3](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)  
3) **Target-region availability** via the **fastest provider-specific endpoints** first, then generic fallbacks:  
   - **Compute (VM sizes/SKUs)**: `az vm list-skus --location <target>` (or REST `Microsoft.Compute/skus?$filter=location eq '<target>'`)—returns `resourceType`, `name`, `locations`, `capabilities`, and **restrictions**. [4](https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-sku-not-available)[5](https://learn.microsoft.com/en-us/rest/api/compute/resource-skus/list?view=rest-compute-2025-04-01)  
   - **Storage account SKUs**: `az storage sku list` (or REST `Microsoft.Storage/skus`)—returns `name`, `locations`, `restrictions`. [6](https://learn.microsoft.com/en-us/cli/azure/storage/sku?view=azure-cli-latest)[7](https://learn.microsoft.com/en-us/rest/api/storagerp/skus/list?view=rest-storagerp-2025-06-01)  
   - **All other types (broad check)**: `az provider list --expand "resourceTypes/locations"` and verify that the `resourceType` includes the target region in its `locations`. (Caveat: some RPs don’t fully populate this; prefer RP-specific “skus” APIs when available.) [8](https://learn.microsoft.com/en-us/cli/azure/provider?view=azure-cli-latest)[9](https://docs.azure.cn/en-us/azure-resource-manager/management/resource-providers-and-types)  
   - (Optional) **VM image SKUs** (publisher/offer): `Microsoft.Compute/locations/{location}/publishers/.../offers/{offer}/skus`. [10](https://learn.microsoft.com/en-us/rest/api/compute/virtual-machine-images/list-skus?view=rest-compute-2025-04-01)  
4) **Regional service availability** pages are used only as **human cross-check** (not in-script): *Products available by region*. [11](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/)[12](https://azure.microsoft.com/en-us/explore/global-infrastructure/products-by-region/table)

---

## 3) Prerequisites & permissions

- **Azure CLI** v2.50+ (with `resource-graph` extension auto-installed on first use of `az graph`). [1](https://learn.microsoft.com/en-us/cli/azure/graph?view=azure-cli-latest)  
- **jq** for JSON processing.  
- Role: **Reader** across target scope(s) is sufficient for ARG and provider/SKU reads.  
- Login: `az login` (or service principal via `az login --service-principal ...`).  
- Access to internet for `prices.azure.com` (public unauthenticated API). [3](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)

---

## 4) Data sources & APIs to use (and how)

### A. Resource inventory (source region)

**Tooling**: Azure Resource Graph (ARG) via `az graph query`  
- **Query scope**:  
  - `--all`: default (tenant-wide across accessible subs)  
  - `--management-groups <mgId>` for MG scope  
  - `--subscriptions <csv>` for explicit subs (script can derive from MG via ARG if needed)  
- **KQL (examples)**:
  - **All resources in source region with key fields**  
    ```kusto
    Resources
    | where tolower(location) == tolower('{SOURCE_REGION}')
    | project id, name, type, location, subscriptionId, resourceGroup,
              sku = tostring(sku.name),
              vmSize = tostring(properties.hardwareProfile.vmSize),
              diskSku = iff(type =~ 'microsoft.compute/disks', tostring(sku.name), ''),
              diskSizeGB = iff(type =~ 'microsoft.compute/disks', toint(properties.diskSizeGB), int(null))
    ```
  - **Quantities by type/SKU**  
    ```kusto
    Resources
    | where tolower(location) == tolower('{SOURCE_REGION}')
    | summarize count() by type, sku = tostring(sku.name), vmSize = tostring(properties.hardwareProfile.vmSize)
    | order by count_ desc
    ```  
  These patterns are officially supported and performant for large estates. [2](https://learn.microsoft.com/en-us/azure/governance/resource-graph/samples/starter)

**CLI execution examples**

```bash
# Tenant-wide (all accessible subs)
az graph query -q "$KQL" --output json > source_inventory.json

# MG-scope
az graph query -q "$KQL" --management-groups "$MGID" --output json > source_inventory.json

# Specific subscriptions (comma-separated)
az graph query -q "$KQL" --subscriptions "$SUBS" --output json > source_inventory.json
```


### B. Pricing meter enrichment

**Endpoint**: `https://prices.azure.com/api/retail/prices` (Azure Retail Prices API)

**Goal**: For each unique resource tuple found in the source-region inventory, look up the corresponding **serviceName**, **serviceFamily**, and **meterName** (plus pricing attributes like `unitOfMeasure`, `retailPrice`, and `currencyCode`) so downstream tooling can join counts → meters.

**Key fields** to capture in output:
- `serviceName`, `serviceFamily`, `meterName`
- `armRegionName`, `armSkuName`
- `skuName`, `productName`, `unitOfMeasure`, `retailPrice`, `currencyCode`
- (optional) `effectiveStartDate`, `effectiveEndDate` to prefer current meters if duplicates surface

**Approach**
1. From `source_inventory.json`, derive **unique tuples** per resource class:
   - **Virtual Machines**: `{ type, vmSize (→ armSkuName), sourceRegion }`
   - **Managed Disks**: `{ type, diskSku (→ skuName/armSkuName), diskSizeGB, sourceRegion }`
   - **Networking** (LB, NAT GW, Public IP): `{ type, sku (if present), sourceRegion }`
   - **Databases/Platform services** (e.g., SQL, Cosmos DB, Redis): `{ type, sku.name (and capacity if present), sourceRegion }`
2. Build **narrow OData filters** to minimize payload and latency:
   - **VM example**  
     ```
     ?$filter=serviceName eq 'Virtual Machines'
             and armRegionName eq '{REGION}'
             and armSkuName eq '{VMSIZE}'
     ```
   - **Disk example (tiered SKUs)**  
     ```
     ?$filter=serviceFamily eq 'Storage'
             and armRegionName eq '{REGION}'
             and (armSkuName eq '{DISK_SKU}' or skuName eq '{DISK_SKU}')
     ```
   - For networking and PaaS services, filter by `serviceFamily`/`serviceName` plus `armRegionName`, then post-filter by `meterName` substring (e.g., `Standard`, `Data Processed`, `Per Gateway Hour`).
3. **Pagination & caching**
   - Follow `NextPageLink` until exhausted.
   - Cache responses in `--cache-dir` keyed by the full request URL (hash). TTL is configurable.
4. **Disambiguation rules**
   - If multiple rows match, pick the most specific combination (prefer exact `armSkuName`, then exact `skuName`, then `productName` substring + `unitOfMeasure`).
   - If Linux/Windows VM pricing must be distinguished, inspect `productName` or `meterName` for OS hints.

**No direct meter**
- Some resource types (containers, policy assignments, empty resource groups, role assignments) have **no direct meter**. Tag them as `no_direct_meter` and list in a separate section of the summary instead of forcing a price lookup.

---

### C. Target-region availability checks (fast path)

**Objective**: Determine if an equivalent resource type/SKU exists in the **target region**, and flag any **restrictions** (subscription not enabled, zone limits, preview, etc.).

1) **Compute (VM sizes/SKUs)**
   - CLI:
     ```bash
     az vm list-skus --location "$TARGET_REGION" --all -o json > compute_skus.json
     ```
   - Parse entries with `resourceType == "virtualMachines"`. Compare `name` to `vmSize`. Inspect `restrictions[]` for:
     - `NotAvailableForSubscription`
     - `Location`/`Zone` limitations (e.g., only Z1/Z2, or only isolated/spot)
   - Treat *any* active restriction as “not generally available” and include details in output.

2) **Storage account SKUs**
   - CLI:
     ```bash
     az storage sku list -o json > storage_skus.json
     ```
   - For each storage SKU used in the source region (e.g., `Standard_LRS`, `Premium_ZRS`, `Standard_GRS`), verify `locations[]` contains `"$TARGET_REGION"`. Record restrictions if present.

3) **Generic provider fallback (broad coverage)**
   - CLI:
     ```bash
     az provider list --expand "resourceTypes/locations" -o json > providers.json
     ```
   - For non-Compute/Storage services, locate the `resourceType` (e.g., `Microsoft.KeyVault/vaults`) and check if `"$TARGET_REGION"` appears within its `locations[]`.  
   - **Caveat**: Some providers under-report `locations`. Prefer RP-specific “skus” APIs when available (e.g., `Microsoft.Network` for App Gateway/NAT GW, `Microsoft.DBforPostgreSQL` for Flexible Server SKUs, etc.).

4) **Optional sanity checks**
   - Validate region spelling & subscription support:
     ```bash
     az account list-locations -o json > sub_locations.json
     ```
   - (Optional) For VM images, use publisher/offer/SKU discovery endpoints if needed to ensure image family parity.

---

## 5) Inventory-to-pricing mapping rules (by resource type)

> Use these heuristics to translate ARG fields into Retail Prices API filters.

- **Virtual Machines**
  - ARG: `properties.hardwareProfile.vmSize` → Retail: `armSkuName`
  - Filter by `serviceName == 'Virtual Machines'` and `armRegionName == sourceRegion`.
  - If OS matters, separate lookups for Linux vs Windows (identify via `meterName` or `productName`).

- **Managed Disks**
  - ARG: `type == Microsoft.Compute/disks`, `sku.name` (e.g., `PremiumV2_LRS`), `properties.diskSizeGB`.
  - Map to Retail with `armSkuName`/`skuName` + `armRegionName`.
  - Use `diskSizeGB` to infer capacity bands (e.g., `P10`, `P15`, `E10`); match via `meterName`/`productName`.

- **Public IP, Load Balancer, NAT Gateway, Application Gateway**
  - Filter by `serviceFamily == 'Networking'` and `armRegionName`.
  - Select meters by SKU tier (`Standard`/`Basic`) and dimension: e.g., gateway-hours, data processed GB, rule units, outbound data.

- **Databases / Caching / Messaging (PaaS)**
  - Use `sku.name` (plus capacity like vCores, nodes, RU/s if available) to filter by `serviceName` or `productName`.
  - Some services have multiple meters per SKU (compute, storage, backup, IOPS). If the script’s scope is strictly meters discovery (not cost calc), record **all** relevant meters for the SKU family and let downstream logic decide which apply.

- **Globally metered or indirect**
  - Bandwidth (egress), Azure AD, or per-API transaction services may not map from a single resource. Mark as `indirect_meter` and list for manual handling.

---

## 6) Script structure (high-level pseudocode)

```text
main():
  # ---- Parse & validate ----
  args = parse_args()
  ensure_installed(az>=2.50, jq)
  verify_login()

  # ---- Inventory via ARG ----
  kql = build_kql(source_region=args.source_region, resource_types=args.resource_types)
  run_arg(kql, scope=args.scope, mg=args.mg, subs=args.subscriptions) -> source_inventory.json

  # ---- Summarize counts ----
  summarize_inventory(source_inventory.json) -> source_inventory_summary.csv

  # ---- Derive unique tuples for lookups ----
  tuples = derive_unique_tuples(source_inventory.json)

  # ---- Pricing lookups (parallel + cached) ----
  prices = []
  parallel_for t in tuples:
    p = retail_prices_lookup(tuple=t, region=args.source_region, cache=args.cache_dir)
    if p:
      prices.append(p)
    else:
      record_unpriced(t)
  write_csv('price_lookup.csv', prices)

  # ---- Target availability ----
  compute_skus   = fetch_or_cache_compute_skus(args.target_region, cache=args.cache_dir)
  storage_skus   = fetch_or_cache_storage_skus(cache=args.cache_dir)
  providers_info = fetch_or_cache_providers(cache=args.cache_dir)

  availability = []
  for t in tuples:
    verdict = check_availability(t, args.target_region, compute_skus, storage_skus, providers_info)
    availability.append(verdict)
  write_json('target_region_availability.json', availability)

  # ---- Exit conditions ----
  if arg_failed or too_many_unpriced or critical_unavailable:
    exit(1)
  exit(0)
```

## 7) Performance guidance

- Run **one large Azure Resource Graph (ARG) query** per scope instead of looping through subscriptions or resource groups to reduce throttling.
- Always include a **region filter** (`location == "<source-region>"`) in ARG queries to shrink payloads before local processing.
- When calling the **Retail Prices API**, always filter using `armRegionName` and a unique SKU identifier such as `armSkuName` or `skuName`.
- Add caching for Retail API pages, compute SKUs by region, storage SKUs, and provider location listings to avoid repeated fetches.
- Use **parallel HTTP calls** (e.g., `xargs -P <threads>`) and **exponential backoff** for transient HTTP errors (429/5xx).
- For VM SKU discovery, constrain payload size with `az vm list-skus --location "<region>"`.

## 8) Error handling and caveats

- **Provider location gaps:** Some resource providers under-populate `locations`; prefer resource-specific SKU APIs when possible.
- **Restrictions:** Treat any ARM SKU restriction (e.g., `NotAvailableForSubscription`, zone limits) as “not generally available” in the target region.
- **Preview/deprecated meters:** When multiple pricing rows match, prefer the newest `effectiveStartDate` and non-preview meter names.
- **Ambiguous meter matches:** Capture all candidates and flag with `ambiguous_meter`.
- **No direct meter types:** Some resources (e.g., resource groups, policy assignments) have no corresponding meter—tag as `no_direct_meter`.
- **Retry logic:** Retry ARM and Retail API transient failures with jitter.

## 9) Example script invocations

```bash
# Tenant-wide scope, East US → West Europe
./inv.sh --all \
--source-region eastus \
--target-region westeurope \
--parallel 12 \
--cache-dir ./.cache

# Management group scope
./inv.sh --mg Contoso-Prod \
--source-region eastus2 \
--target-region uksouth

# Resource group scope
./inv.sh --rg 00000000-0000-0000-0000-000000000000:WorkloadRG \
--source-region westus3 \
--target-region centralus
```

## 10) Data schemas

- **source_inventory_summary.csv**

```json
subscriptionId,resourceGroup,location,type,sku,vmSize,diskSku,diskSizeGB,count
```

- **price_lookup.csv**

```json
type,armSkuName,armRegionName,serviceName,serviceFamily,meterName,productName,skuName,unitOfMeasure,retailPrice,currencyCode
```

- **target_region_availability.json**

```json
[
  {
    "type": "Microsoft.Compute/virtualMachines",
    "armSkuName": "Standard_D8s_v5",
    "targetRegion": "westeurope",
    "available": true,
    "restrictions": []
  },
  {
    "type": "Microsoft.Storage/storageAccounts",
    "sku": "Standard_GRS",
    "targetRegion": "westeurope",
    "available": true,
    "restrictions": []
  },
  {
    "type": "Microsoft.KeyVault/vaults",
    "targetRegion": "westeurope",
    "available": true,
    "evidence": "provider lookup shows westeurope in supported locations"
  }
]
```

## 11) Security and authentication guidance

- Use standard Azure CLI authentication via `az login` or a service principal with Reader or higher permissions.
- Do not store credentials in cache directories.
- Required outbound endpoints: Azure Resource Manager and Azure Retail Prices API.
- Azure CLI handles token refresh—no custom token handling needed.

## 12) Acceptance criteria

- source_inventory_summary.csv contains accurate counts for all resources in the chosen source region and scope.
- price_lookup.csv correctly maps all mappable resources to `serviceName`, `serviceFamily`, and `meterName`.
- target_region_availability.json includes a clear availability status for each resource type/SKU in the target region.
- Retail API calls are efficiently filtered, paginated, cached, and retried.
- Script exits non-zero upon: ARG query failures, excessive pricing lookup failures, or missing/invalid target-region SKU checks.

## Implementation notes (for the coding agent)

- Use Azure CLI where possible; fall back to REST only when required.
- Normalize inventory data early so joins are predictable.
- Implement simple reusable caching:

```text
if cache exists and not expired:
  use cache
else:
  fetch → save → return data
```

- Structure the script into modular components: inventory.sh, pricing.sh, availability.sh, util_http.sh, util_cache.sh.
- Maintain a compact run.log file with: ARG runtime, Retail API pages fetched, cache hit rate, and errors/retry counts.