# Copilot Instructions

## Architecture

This repo is an Azure regional migration analysis tool with three main layers:

1. **Shell CLI** (`scripts/root/inv.sh`, `scripts/root/services_compare.sh`) — Bash entry points that orchestrate Azure resource inventory, SKU availability, pricing, and quota analysis. Library modules live in `lib/` and are sourced in order (order matters). `inv.sh` does inventory-driven analysis (requires Azure resources); `services_compare.sh` does region-only provider/SKU comparison (no inventory needed).

2. **Python CLI** (`src/azure_compare_cli/`) — Companion package for curated service catalog builds (JSON + SQLite) and Rich console rendering of provider comparison output. Installed editably into `.venv/` via `scripts/bootstrap_python.sh`. Shell scripts auto-detect and prefer the Python renderer when `.venv` is available.

3. **Azure-hosted pipeline** — Three components deployed via `azd up`:
   - `web_app/` — Express server + React (Fluent UI v9) SPA on App Service. Vite build, Node ≥22.12.
   - `azure_pipeline/function_app/` — Python Azure Functions backend (containerized). Handles refresh, comparison retrieval, runs history. Uses Azure Table Storage and Blob Storage.
   - `infra/` — Bicep IaC (App Service, Function App, ACR, VNet, private endpoints, private DNS). Deployment orchestrated by `azure.yaml` hooks (`scripts/azd/`).

## Build and Test Commands

### Python CLI
```bash
# Bootstrap the Python environment
./scripts/bootstrap_python.sh

# Run the CLI
.venv/bin/python -m azure_compare_cli --help
```

### Web App
```bash
cd web_app
npm install
npm run build     # Vite production build → dist/
npm run dev       # Vite dev server
npm start         # Express production server
```

### Playwright E2E Tests (web app)
```bash
cd web_app
npx playwright test                    # Run all tests
npx playwright test tests/app.spec.js  # Run a single test file
```

### Shell Tests
```bash
# Run all test suites
./tests/run_all_tests.sh

# Run individual test suites
./tests/test_quota_analysis.sh
./tests/test_services_compare_regressions.sh
./tests/test_sku_provider.sh
./tests/e2e_test.sh
./tests/quick_validation.sh
```

### Azure Functions (backend)
```bash
cd azure_pipeline/function_app
pip install -r requirements.txt
python -m pytest tests/
```

### Infrastructure
```bash
azd provision --preview   # Preview Bicep changes
azd up                    # Full deploy (provision + deploy)
./deploy.sh --resource-group <rg> --location <region>  # One-command wrapper
```

## Key Conventions

- **Shell scripts use `set -euo pipefail`** (or `set -uo pipefail` for `inv.sh`). All library modules in `lib/` are sourced, not executed as subprocesses.
- **Sovereign cloud support** — Scripts derive ARM endpoints, authority hosts, and management scopes from the active Azure CLI cloud (`az cloud show`). Never hardcode public Azure endpoints. Region lists are cloud-scoped; public/Government region mixing is rejected early.
- **Caching** — Shell scripts cache API responses in `.cache/`. The web app server has an in-memory cache with configurable TTL. Cached data is never committed.
- **Python uses `from __future__ import annotations`** at the top of every module for forward-reference type hints.
- **Web app UI** uses Fluent UI React v9 (`@fluentui/react-components`). The Express server (`server.js`) is both an API proxy to the Function App and a static file server for the Vite build output.
- **Function App auth** uses managed identity + Entra bearer tokens (not function keys) for web-to-function communication.
- **Output artifacts** go to `output/` (shell analysis results) and `data/generated/` (catalog snapshots, SQLite DB). Neither directory is committed.
- **Curated service catalog** source-of-truth is `data/feature_catalog/services.json`. Generated artifacts (snapshots, SQLite, identity maps) are built by the Python CLI and consumed by both shell scripts and the hosted pipeline.
