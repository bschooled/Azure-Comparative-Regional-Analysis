# Azure Function Scaffold

This Function app is the hosted scaffold for the optional Azure pipeline.

It currently provides:

- A daily timer-triggered refresh entrypoint.
- A manual HTTP refresh endpoint at `/api/refresh`.
- A Microsoft Entra-protected comparisons query endpoint at `/api/comparisons`.
- A Microsoft Entra-protected health endpoint at `/api/health`.
- A Microsoft Entra-protected runs listing endpoint at `/api/runs`.
- A Microsoft Entra-protected private-pricing hydration endpoint at `/api/pricing/hydrate`.
- A Microsoft Entra-protected private-pricing status endpoint at `/api/pricing/status`.
- Table Storage persistence for the current comparison projection, historical run data, and refresh run metadata.
- Blob-backed pricing cache for private price-sheet artifacts and normalized indexes.
- Two comparison modes: inventory-based and full regional.

Retail pricing is seeded inline for inventory comparisons where the resource surface can be mapped to a direct retail meter. Private price sheets are intentionally hydrated through a separate endpoint so billing-scope discovery, ZIP downloads, and normalization do not block the main comparison refresh path.

The current deployment path targets Linux Elastic Premium with a dedicated app VNet, storage private endpoints, private DNS, identity-based host storage, and container-based code deployment from Azure Container Registry. The Function App is intended to be reached through the App Service web frontend rather than directly by end users.

## Local execution

1. Create a local config file from `local.settings.sample.json`.
2. Install Python dependencies from `requirements.txt`.
3. Start the Azure Functions host with `func start` from this directory.

## Hosted deployment

Use the repo deployment helper from the project root:

```bash
./scripts/deploy_azure_pipeline.sh --resource-group <rg-name>
	--web-auth-client-id <entra-app-client-id>
```

Or create the Entra app registration during deployment:

```bash
./scripts/deploy_azure_pipeline.sh --resource-group <rg-name>
	--create-web-auth-app
```

The deployed Azure Function App targets Elastic Premium. The repo is configured for `azd`, which manages deployment environment state in `.azure/<environment>/.env` and provides the infrastructure outputs used by the deployment helper.

This deployment path intentionally avoids Azure Files content shares because Premium Functions still require key-based Azure Files access, while this repo targets environments where shared-key access is blocked. Host storage uses identity-based `AzureWebJobsStorage` settings, and code is deployed by building a custom Function container image in Azure Container Registry and updating the Function App to that image with managed-identity-based registry pulls.

The Function App HTTP surface is protected by App Service authentication with a dedicated single-tenant Entra application. The App Service web frontend acquires bearer tokens for that API with its own managed identity, and the deployment helper authorizes the web app identity for those calls.

The Function container uses a digest-pinned Azure Functions Python 3.12 base image and installs current `cryptography` wheels. When either dependency changes, rebuild the container and run the Function integration tests because native wheel and host-library compatibility can change across image releases.

Direct `azd` flow:

```bash
azd env new <env-name> --location <region> --subscription <subscription>
azd env set AZURE_RESOURCE_GROUP <rg-name>
azd up
```

The `preprovision` hook now creates or reuses the web and Function Entra registrations automatically, and the deployment helper persists discovered live resource names back into the selected `azd` environment so reruns remain idempotent even if `azd env refresh` cannot recover outputs from historic deployment state.

Use `azd provision` when only Bicep changes need to be applied, rerun `./scripts/deploy_azure_pipeline.sh --resource-group <rg-name>` for code updates, and use `azd down --no-prompt` when tearing down the environment. The deployment helper also updates the Entra app registration redirect URI to the final App Service hostname after provisioning, because that callback URL is only known once the web app has been created.

## Expected next step

Continue hardening the hosted comparison generation so the App Service proxy remains the only intended consumer of the Function read endpoints while all storage access stays private to the Function runtime.