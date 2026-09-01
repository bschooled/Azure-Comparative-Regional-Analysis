# Live Implementation Tracker

Date: 2026-05-06
Scope: Hosted comparison app hardening, UI implementation slices, and repo-side tracking of the live repair thread.

## Original Operating Prompt

Primary user direction for this execution thread:

> The function app is failing to start, you are to directly troubleshoot with the CLI and iterate and repair until its working - Any improvements or hardening you make needs to ported to the code in this repo so it doesn't happen again.

That operational prompt expanded during the same thread into the hosted web experience:

> Check the hosted web app, audit the UI for improvements, and carry the fixes back into the repo.

## Current Continuation Prompt

This implementation continuation is being tracked from the current request:

> Continue through implementation slices.
> Also make sure the context of this chat and the original prompt are being recordes in docs/ appropriately for tracking.

## Session Context

This thread has combined four connected workstreams:

1. Live Azure Function App startup diagnosis and repair through the Azure CLI.
2. Web App overview cleanup and hosted UX audit.
3. Backend comparison/runtime fixes that were pushed back into repo code.
4. Live UI sweep follow-up work to turn the hosted app into a migration-planning-first surface.

The key implementation rule for this thread has remained stable: live fixes are not considered complete unless the same correction or hardening change is reflected back into the repository.

## Planning Anchors

- [docs/Implementation/Spec.md](<repo-root>/docs/Implementation/Spec.md)
- [docs/Implementation/LIVE_UI_SWEEP_PLAN.md](<repo-root>/docs/Implementation/LIVE_UI_SWEEP_PLAN.md)
- [web_app/src/App.jsx](<repo-root>/web_app/src/App.jsx)

## Slice Tracking

### Slice 1: Runs Correctness And UI Polish

Status: Completed

- Fixed the duplicated status defect in the Runs cards by removing status text from the secondary metadata line and leaving status ownership with the visible badge.
- Validation path: frontend production build.

### Slice 2: Reframe Results As A Triage Workspace

Status: Completed

- Add a top-level triage summary to Results.
- Add an explicit action focus for `region gaps`, `identity review`, `pricing follow-up`, and `move-ready` rows.
- Order visible result cards so higher-action buckets appear before clean matches.

### Slice 3: Advanced Diagnostics Disclosure

Status: Completed

- Raw fallback diagnostics and provider metadata differences now sit behind explicit disclosure in the result details.
- Planner-facing guidance remains visible in the canonical identity section when a row is still using fallback identity.

### Slice 4: Collapsed Card Compression

Status: Completed

- Collapsed result cards now lead with short action-oriented copy instead of long diagnostic narrative.
- Pricing copy in the collapsed summary is reduced to a compact availability signal and leaves the evidence in the expanded view.

### Slice 5: Overview To Results Handoff

Status: Completed

- Overview now tells the user exactly how Results is ordered after execution and what to review first.
- The latest run remains visible as the continuation point from Overview into Results and Runs.

### Slice 6: Pricing Overlay Naming And Seeded Service Identity

Status: Completed

- A live sweep of the hosted pricing overlays confirmed the same issue in both Virtual Machines and Managed Disks: the first filter tier still used retail-engine labels such as `Product name`, `SKU name`, and `Meter name`.
- The web pricing filters now use service-first language such as `Service scope`, `VM size`, `Disk SKU`, and `Charge detail`, with helper copy that explains the intended filter progression.
- The curated feature catalog now pre-seeds friendly aliases and pricing identity data for Azure Storage, Virtual Machines, and Managed Disks so the non-AI path has canonical service-first naming available in generated artifacts.

### Slice 7: Capability Guidance Rehydration

Status: Completed

- The next continuation slice is moving seeded capability notes away from generic commentary and toward operator-facing value statements.
- The controlling source is [azure_pipeline/function_app/shared/curated_catalog.py](<repo-root>/azure_pipeline/function_app/shared/curated_catalog.py), because the capability matrix currently forwards `sourceNotes` and `targetNotes` directly into the live UI.
- This slice is focusing first on the highest-traffic curated services: App Service, Functions, Container Apps, SQL Database, SQL Managed Instance, Azure Storage, and AKS.
- The refreshed catalog guidance has now been deployed through the Function App container path without redeploying the hosted web app.

### Slice 8: Results Hardening And AKS Validation

Status: Completed

- Removed three supplemental capability rows from newly generated comparison payloads: `provider_surface_area`, `metadata_uniques`, and `zone_support_posture`.
- Added a frontend compatibility filter so those same rows stay hidden even when an older cached run still carries them.
- Removed the stale empty fifth detail column in the capability matrix by aligning the rendered grid to the visible five-column layout.
- Split fast search input updates from lower-priority result filtering so the hosted Results search field no longer drops characters during active filtering.
- Reservation and savings-plan display values are now amortized to monthly equivalents instead of only relabeling the term-based totals.
- Live AKS validation now uses a fresh regional run rather than the narrower inventory run, because the hosted inventory slice does not include the AKS result row.

### Slice 9: Provider-Type Curation And Umbrella Search Tags

Status: Completed

- Curated capability rows now explicitly claim the core provider resource types for Azure Cosmos DB, Azure Container Registry, Azure Service Bus, Azure AI Services, Azure AI Search, Azure Machine Learning, Azure Synapse Analytics, Azure Databricks, and Azure Data Factory.
- The unmapped-provider expansion now shows only true residual provider metadata after curated capability rows claim the resource types they represent.
- Cosmos DB now treats `databaseaccounts`, `mongoclusters`, and `cassandraclusters` as first-class curated capability coverage instead of leaving them as raw provider leftovers.
- ACR now treats `registries` as curated capability coverage, and Service Bus now treats `namespaces` as curated capability coverage.
- Curated identity provenance now carries service discovery terms so umbrella searches can resolve useful service groups even when Azure exposes the underlying service families instead of a single parent wrapper.
- The current umbrella-tag pass covers live search terms such as `foundry`, `openai`, `rag`, `fabric`, `acr`, and `namespace`.

### Slice 10: Regional AZ Posture And Overview Summary

Status: Completed

- Fixed the shell AZ-region helper so it can resolve zone presence without relying on pre-seeded external cache variables, which restores real `true` and `false` values for regions such as East US and West US instead of falling back to `unknown`.
- The Python catalog resolver now treats default zonal support as unverified when the region-level AZ evidence is still unknown, rather than rendering a confident positive posture from curated defaults alone.
- Results triage now treats source/target AZ mismatches as region gaps, so rows no longer fall into `move-ready` when one region exposes AZs and the other does not.
- The Overview side column now reuses the existing summary card to show source region, target region, service-family count, and AZ posture without adding another top-level surface.
- Follow-up fix: the Overview regional summary now stays aligned to the currently selected form regions instead of leaking AZ posture and family counts from a different latest run, which had made the hosted page read as broken when the latest run pair differed from the current selection.

## Verification Log

- 2026-05-06: `npm run build` succeeded in [web_app](<repo-root>/web_app) after the first Runs fix.
- 2026-05-06: `npm run build` succeeded again after the Results triage layer, action-bucket ordering, and tracker-document additions.
- 2026-05-06: `npm run build` succeeded again after moving fallback diagnostics and provider metadata differences behind advanced disclosure.
- 2026-05-07: `npm run build` succeeded again after collapsed-card compression and Overview-to-Results handoff updates.
- 2026-05-07: `npm run build` succeeded again after the pricing filter vocabulary moved from retail-engine terms to service-first naming in the hosted web app.
- 2026-05-07: `PYTHONPATH=src python3 -m azure_compare_cli.__main__ build-catalog --source data/feature_catalog/services.json --output-json data/generated/feature_catalog.snapshot.json --output-sqlite data/generated/feature_catalog.db --output-identity-json data/generated/canonical_service_identity.snapshot.json` completed successfully and regenerated the seeded identity artifacts with Azure Storage, Virtual Machines, and Managed Disks pricing names.
- 2026-05-07: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --environment-name azcomparev3 --subscription <subscription-id> --skip-provision --skip-refresh` completed successfully, deployed the App Service package, and the site readiness probe returned HTTP 200.
- 2026-05-07: capability guidance copy was refreshed in the curated catalog for App Service, Functions, Container Apps, SQL Database, SQL Managed Instance, Azure Storage, and AKS so the capability matrix can explain operator value instead of repeating generic commentary.
- 2026-05-07: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --environment-name azcomparev3 --subscription <subscription-id> --skip-provision --skip-web-deploy --skip-refresh` completed successfully, pushed container image `<acr-name>.azurecr.io/function-app:20260507t160450z`, and updated Function App `<func-app-name>`.
- 2026-05-07: `az functionapp function list --resource-group <resource-group> --name <func-app-name> --subscription <subscription-id> --query "[].name" -o tsv` returned the expected indexed functions including `health_check`, `list_comparisons`, `list_runs`, and `manual_refresh` after the image swap.
- 2026-05-07: `npm run build` succeeded in [web_app](<repo-root>/web_app) after the Results search-state split, capability-row hide path, matrix-column cleanup, and monthly reservation-pricing conversion.
- 2026-05-07: `python3 -m py_compile azure_pipeline/function_app/shared/azure_queries.py azure_pipeline/function_app/shared/curated_catalog.py` succeeded after removing supplemental capability-row injection and continuing curated operator guidance.
- 2026-05-07: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --environment-name azcomparev3 --subscription <subscription-id> --skip-provision --skip-refresh` completed successfully, pushed container image `<acr-name>.azurecr.io/function-app:20260507t162431z`, updated the hosted web app, and left the site healthy.
- 2026-05-07: `POST /api/refresh` with `comparisonMode=inventory` returned run `20260507162857` with `recordCount: 16`, confirming the new payload shape no longer emits the three removed supplemental capability rows.
- 2026-05-07: `POST /api/refresh` with `comparisonMode=regional` returned run `20260507163044` with `recordCount: 29`, and the hosted Results view successfully filtered to `Azure Kubernetes Service` for live validation.
- 2026-05-07: Live AKS validation on run `20260507163044` confirmed the expanded capability matrix renders only the curated ten capability rows, shows five visible columns (`Capability`, both regions, `Priority`, and `What this gives you`), and no longer shows the removed supplemental rows or the empty column.
- 2026-05-07: a focused Python validation against the edited comparison slice confirmed the targeted services now produce no residual `Unmapped provider metadata` sections for their core provider types, and that the new discovery terms are present in identity provenance for `openai`, `foundry`, `rag`, and `fabric` searches.
- 2026-05-07: `npm run build` succeeded in [web_app](<repo-root>/web_app) after extending the hosted Results search index with curated discovery keywords.
- 2026-05-07: `python3 -m py_compile azure_pipeline/function_app/shared/curated_catalog.py azure_pipeline/function_app/shared/azure_queries.py` succeeded after the provider-type capability mapping and residual-unmapped filtering changes.
- 2026-05-07: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --environment-name azcomparev3 --subscription <subscription-id> --skip-provision --skip-refresh` completed successfully, pushed container image `<acr-name>.azurecr.io/function-app:20260507t170055z`, and redeployed the hosted web app.
- 2026-05-07: `POST /api/refresh` with `comparisonMode=regional` returned run `20260507170324` with `recordCount: 29`; live payload validation showed zero residual unmapped-provider sections for Azure Cosmos DB, Azure Container Registry, Azure Service Bus, Azure AI Services, Azure AI Search, Azure Machine Learning, Azure Synapse Analytics, Azure Databricks, and Azure Data Factory.
- 2026-05-07: hosted Results search on run `20260507170324` returned `Azure AI Search`, `Azure AI Services`, and `Azure Machine Learning` for the live query `foundry`, confirming the umbrella-tag search path is active in the deployed UI.
- 2026-05-07: `source lib/python_cli.sh && region_has_availability_zones eastus|westus|canadacentral|swedencentral` now resolves `eastus=true`, `westus=false`, `canadacentral=true`, and `swedencentral=true`, confirming the AZ helper no longer depends on missing shell state.
- 2026-05-07: `python3 - <<'PY' ... resolve_zone_mode(...) ... PY` returned `zone-support-unverified` for unknown regional evidence and `region-without-zones` for West US, confirming the catalog resolver now handles missing AZ evidence conservatively.
- 2026-05-07: `python3 -m py_compile src/azure_compare_cli/catalog.py` succeeded after the AZ posture hardening.
- 2026-05-07: `npm --prefix web_app run build` succeeded after the Results triage and Overview regional-summary updates.
- 2026-05-07: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --subscription <subscription-id> --skip-provision --skip-refresh` completed successfully, pushed container image `<acr-name>.azurecr.io/function-app:20260507t204436z`, and redeployed the hosted web app and function app.
- 2026-05-08: `npm --prefix web_app run build` succeeded after the Overview summary alignment fix that prevents stale latest-run AZ/family data from appearing under the current form selection.
- 2026-05-08: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --subscription <subscription-id> --skip-provision --skip-refresh` completed successfully, pushed container image `<acr-name>.azurecr.io/function-app:20260508t000129z`, and redeployed the hosted web app.
- 2026-05-08: browser validation against `https://<web-app-name>.azurewebsites.net/` confirmed the hosted Overview now keeps the regional summary on the selected `canadacentral -> eastus` form values and shows `Run comparison to verify AZ posture` instead of stale `eastus -> westus` AZ data.
- 2026-05-08: AZ-source research confirmed the reliable region-level programmatic signal is the ARM `GET /subscriptions/{subscriptionId}/locations?api-version=2022-12-01` response's top-level `availabilityZoneMappings` field. In this environment, `az account list-locations` returned incomplete/null zone mapping data, so `lib/region_mapping.sh` and `lib/python_cli.sh` now prefer `az rest` against the ARM locations API and only fall back to `az account list-locations` as a degraded path.
- 2026-05-08: the hosted Function App was still using service-level zone defaults without any region-level AZ evidence, so West US could still render as zonal after a live refresh. `shared/azure_queries.py` now loads region AZ posture from the ARM locations API and passes it into `shared/curated_catalog.py`, which now downgrades no-zone regions to `region-without-zones` and unknown evidence to `zone-support-unverified`.
- 2026-05-08: `python3 -m py_compile azure_pipeline/function_app/shared/curated_catalog.py azure_pipeline/function_app/shared/azure_queries.py src/azure_compare_cli/catalog.py` succeeded after the AZ-source change, and a focused resolver check returned `region-without-zones` for `westus=false`.
- 2026-05-08: `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --subscription <subscription-id> --skip-provision --skip-web-deploy --skip-refresh` completed successfully and pushed Function App image `<acr-name>.azurecr.io/function-app:20260508t002114z`.
- 2026-05-08: fresh hosted run `20260508002344` for `eastus -> westus` now returns `targetRegion.regionHasAvailabilityZones = false` and `targetRegion.zoneSupport.mode = region-without-zones` for representative services including Azure API Management and Azure Kubernetes Service.
- 2026-05-08: the hosted refresh path still reported `Request failed` for long-running runs even when `manual_refresh` later completed successfully. The web UI submit flow in `web_app/src/App.jsx` now treats that as a recoverable timeout-class failure by polling `/api/runs` for a newly completed matching run and loading Results automatically when it appears.
- 2026-05-08: `npm --prefix web_app run build` succeeded after the refresh recovery change, `./scripts/deploy_azure_pipeline.sh --resource-group <resource-group> --subscription <subscription-id> --skip-provision --skip-refresh` redeployed the hosted web app with Function image `<acr-name>.azurecr.io/function-app:20260508t005348z`, and hosted `/api/health` returned `latestRunId: 20260508004220` with `latestRunStatus: completed` after deployment.
- 2026-05-07: direct shell access to the live protected endpoints still returns `403`, and Azure CLI audience consent for the Function App API is not currently granted to the CLI application, so post-deploy live payload validation from this shell remains blocked pending an interactive consent flow or browser-authenticated validation path.

## Next Execution Order

1. Validate the deployed AZ posture and overview summary through a browser-authenticated session, since the shell path remains blocked by App Service auth and missing API consent for Azure CLI.
2. Continue the provider-type curation sweep on the remaining live services that still surface meaningful residual metadata after the current high-value pass.
3. Expand umbrella discovery tags further where live search terms suggest missing groupings beyond `foundry`, `openai`, and `fabric`.
4. Use the newly seeded service identity data to replace more raw retail product labels with curated service-scope options in storage-oriented overlays.