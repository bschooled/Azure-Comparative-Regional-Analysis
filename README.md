# Azure Comparative Regional Analysis

Automated Azure regional migration analysis: inventories resources, maps pricing, checks SKU availability, and generates cross-region comparison data — with a full hosted web experience or standalone CLI scripts.

## Quick Start — Hosted Deployment

The primary deployment path uses Azure Developer CLI (`azd`) to provision an App Service web app, a containerized Python Function App, storage, networking, and identity resources.

### Prerequisites

| Tool | Purpose | Install |
|------|---------|---------|
| Azure CLI (`az`) | Azure management | [aka.ms/install-azure-cli](https://aka.ms/install-azure-cli) |
| Azure Developer CLI (`azd`) | Deployment orchestration | [aka.ms/install-azd](https://aka.ms/install-azd) |
| Docker | Local Function App container builds | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| GitHub CLI (`gh`) | Resolve pinned release artifacts for upgrades | [cli.github.com](https://cli.github.com/) |
| Python 3 | Function App runtime | Your package manager |
| jq | JSON processing | Your package manager |
| Node.js 22+ | Web app build | [nodejs.org](https://nodejs.org/) |

### One-command deploy

```bash
az login
./deploy.sh --resource-group rg-analysis --location canadacentral
```

`deploy.sh` performs full preflight validation (tools, login, Bicep, cloud context), creates or selects an `azd` environment, provisions infrastructure, and deploys to paired `qa` slots by default. QA uses isolated storage tables and containers, disables the scheduled refresh trigger, and retains the production access restrictions.

Deploy an exact successful GitHub release to QA, then promote that tested release by swapping the Function slot first and the Web slot second:

```bash
./deploy.sh --resource-group rg-analysis --environment-name rg-analysis \
    --upgrade --release-tag build-YYYYMMDD-HHMMSS-abcdef0

./deploy.sh --resource-group rg-analysis --environment-name rg-analysis \
    --slot prod
```

Omit `--release-tag` to deploy the latest release to QA. Production never follows `latest`; it promotes the immutable image and web package already running in QA. Re-running the production command reverses the swap and provides immediate rollback to the release left in QA.

### Deployment modes

**Entra ID integrated auth (default)** — Creates a Microsoft Entra app registration for the web app. Users authenticate with their Azure AD identity.

```bash
./deploy.sh --resource-group rg-analysis --location canadacentral
```

**IP-restriction mode** — No Entra app registration required. The web app is restricted to your public IP address. Useful for demos, personal use, or environments where Entra app registration is not available.

```bash
./deploy.sh --resource-group rg-analysis --location canadacentral --ip-restrict
```

Add more allowed IPs or CIDRs:

```bash
./deploy.sh --resource-group rg-analysis --location canadacentral \
    --ip-restrict --allow-ip 203.0.113.0/24
```

### Azure Government

```bash
az cloud set --name AzureUSGovernment
az login
./deploy.sh --resource-group rg-analysis --location usgovvirginia --ip-restrict
```

The deployment enforces cloud-region alignment: Government regions only work with `AzureUSGovernment`, and public regions only with public Azure. A service availability preflight validates that all required providers exist in the selected regions before provisioning.

### Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    App Service (Web)                     │
│    Node.js / Express + React (Fluent UI v9) SPA          │
│    Entra ID auth  OR  IP-restriction access control      │
│    Proxies /api/* to Function App via managed identity   │
├────────────────────────────┬─────────────────────────────┤
│       VNet Integration     │      Private Endpoints      │
├────────────────────────────┼─────────────────────────────┤
│  Azure Functions (Python)  │  Azure Storage              │
│  Containerized via ACR     │  Table + Blob + Queue       │
│  ARM queries, SKU checks,  │  Comparison data, runs,     │
│  pricing, curated catalog  │  refresh queue              │
├────────────────────────────┴─────────────────────────────┤
│  Azure Container Registry        Managed Identity        │
│  Private DNS Zones        Log Analytics + App Insights   │
└──────────────────────────────────────────────────────────┘
```

**Azure services deployed:**

| Service | Purpose |
|---------|---------|
| App Service (S1 Linux) | Web app hosting + API proxy |
| Azure Functions (Premium, container) | Backend: ARM queries, pricing, SKU comparison |
| Azure Container Registry | Function App container images |
| Storage Account (private) | Table Storage, Blob, Queue for comparison data |
| Storage Account (deployment) | Function App deployment packages |
| Virtual Network | Isolated app network with delegated subnets |
| Private Endpoints + DNS | Private connectivity to storage |
| Managed Identity (system + user) | Passwordless service-to-service auth |
| Log Analytics + Application Insights | Centralized platform logs, metrics, and application telemetry |

### Advanced deployment

Use the deployment helper directly for additional control:

```bash
# Full deployment with existing Entra app registration
./scripts/deploy_azure_pipeline.sh --resource-group rg-analysis \
    --web-auth-client-id <client-id>

# Code-only redeployment (skip infrastructure)
./scripts/deploy_azure_pipeline.sh --resource-group rg-analysis --skip-provision

# Prepare environment values only (no provisioning or deployment)
./scripts/deploy_azure_pipeline.sh --resource-group rg-analysis --prepare-only
```

Or drive `azd` directly:

```bash
azd env new my-env --location canadacentral --subscription <sub-id>
azd env set AZURE_RESOURCE_GROUP rg-analysis
azd up
```

## Standalone CLI Scripts (Secondary)

The standalone shell scripts perform the same analysis without hosting anything in Azure. They run locally against the Azure APIs using your CLI credentials.

Scripts live under `scripts/root/`:

```bash
# Inventory-driven analysis (ARG + pricing + availability + comparative tables)
scripts/root/inv.sh --all --source-region eastus --target-region westeurope

# Inventory-driven analysis for a specific resource group
scripts/root/inv.sh --rg <subId>:<rgName> --source-region eastus --target-region westeurope

# Region-only comparison (no inventory needed)
scripts/root/services_compare.sh --source-region westus2 --target-region swedencentral

# Pretty-print an existing comparison JSON
scripts/root/comparative_analysis.sh output/westus2_vs_swedencentral_providers.json
```

### Standalone examples

```bash
# Management group scope
scripts/root/inv.sh --mg <managementGroupId> --source-region eastus2 --target-region uksouth

# Resource group scope
scripts/root/inv.sh --rg <subId>:<rgName> --source-region westus3 --target-region centralus

# Pre-generated inventory
scripts/root/inv.sh --all --source-region centralus --target-region swedencentral \
    --inventory-file test_inventories/inventory_compute.json

# Filter resource types
scripts/root/inv.sh --all --source-region eastus --target-region westeurope \
    --resource-types "Microsoft.Compute/virtualMachines,Microsoft.Compute/disks"

# Region-only comparison
scripts/root/services_compare.sh --source-region westus2 --target-region swedencentral --output-dir output

# Azure Government (standalone)
az cloud set --name AzureUSGovernment && az login
scripts/root/inv.sh --all --source-region usgovvirginia --target-region usgovtexas
scripts/root/services_compare.sh --source-region usgovvirginia --target-region usgovtexas
```

### Output files

**Inventory workflow** (`inv.sh`):
- `output/source_inventory.json` — Raw ARG output
- `output/source_inventory_summary.csv` — Resource counts by type and SKU
- `output/price_lookup.csv` — Pricing meter mappings
- `output/target_region_availability.json` — SKU availability in target region
- `output/quota_source_region.json` / `output/quota_target_region.json` — Service quotas
- `output/quota_summary.csv` — Quota usage summary

**Region comparison** (`services_compare.sh`):
- `<source>_vs_<target>_providers.json` — JSON source-of-truth
- `<source>_vs_<target>_providers.csv` — SKU-granular CSV

## Python Renderer and Catalog Builder

The repo includes a Python companion CLI for curated service catalog builds and rich console rendering:

```bash
./scripts/bootstrap_python.sh

.venv/bin/python -m azure_compare_cli build-catalog \
  --source data/feature_catalog/services.json \
  --output-json data/generated/feature_catalog.snapshot.json \
  --output-sqlite data/generated/feature_catalog.db \
  --output-identity-json data/generated/canonical_service_identity.snapshot.json
```

`services_compare.sh` and `comparative_analysis.sh` prefer the Python renderer when `.venv` is available, falling back to the legacy shell formatter otherwise.

See the [Curated Service Catalog reference](docs/Reference/CURATED_SERVICE_CATALOG.md)
for the source schema, identity mapping, generated artifacts, consumer behavior,
validation, and contribution workflow.

## Azure Government and Sovereign Clouds

Both the hosted app stack and standalone scripts derive ARM endpoints, management scopes, and authority hosts from the active Azure CLI cloud. Region lists are cloud-scoped, and public/Government region mixing is rejected early.

- Re-authenticate after switching clouds (`az login`).
- `inv.sh` skips pricing enrichment in sovereign clouds (Retail Prices API supports Commercial Cloud only).
- The web app and Function app receive cloud metadata as app settings for runtime alignment.
- The deployment helper writes a service validation report before provisioning so you can confirm required services exist in the selected regions.

## Requirements

- Azure CLI v2.50+
- jq, curl
- Reader role or higher in Azure
- Docker (for hosted deployment)
- Node.js 22+ (for web app build)
- Python 3 (for Function App and optional CLI)

## Documentation

- [Quick Start](docs/Usage/QUICKSTART.md) — Common scenarios and output review
- [Deployment diagnostics](docs/DEPLOYMENT_DIAGNOSTICS.md) — Centralized logs, metrics, queries, and operations
- [Inventory Workflow](docs/Usage/README_USAGE.md) — Full `inv.sh` usage and outputs
- [Region-Only Comparison](docs/Usage/SERVICES_COMPARE.md) — Full `services_compare.sh` usage and outputs
- [Curated Service Catalog](docs/Reference/CURATED_SERVICE_CATALOG.md) — Schema, builds, identity, consumers, and maintenance

## Repository Structure

```
deploy.sh                          # One-command deployment wrapper
azure.yaml                        # azd project configuration
infra/                             # Bicep IaC (App Service, Functions, VNet, etc.)
web_app/                           # Express + React SPA
azure_pipeline/function_app/       # Python Azure Functions backend
scripts/
  root/                            # Standalone CLI scripts (inv.sh, services_compare.sh, etc.)
  deploy_azure_pipeline.sh         # Advanced deployment helper
  azd/                             # azd lifecycle hooks
  bootstrap_python.sh              # Python environment setup
lib/                               # Shared shell library modules
data/feature_catalog/              # Curated service catalog source
src/azure_compare_cli/             # Python CLI package
tests/                             # Shell test suites
examples/                          # Example invocations
docs/                              # Extended documentation
```
