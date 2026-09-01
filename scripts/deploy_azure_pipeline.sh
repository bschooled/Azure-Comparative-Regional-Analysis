#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Deploy the optional Azure-hosted regional analysis pipeline.

Usage:
    ./scripts/deploy_azure_pipeline.sh --resource-group <name> [options]

Options:
  --resource-group <name>   Target resource group. Required.
  --environment-name <name> azd environment name. Default: derived from resource group.
  --subscription <id|name>  Azure subscription to target.
  --location <azure-region> Azure location. Preferred when the resource group does not already exist.
  --source-region <azure-region> Source region used by the seeded comparison refresh. Default: deployment location.
  --target-region <azure-region> Target region used by the seeded comparison refresh. Default: eastus.
  --name-prefix <value>     Resource naming prefix. Default: azcomparereg
  --environment-label <val> Logical environment label used by the Bicep. Default: dev
    --site-suffix <value>     Short alphanumeric suffix appended to hosted site names. Default: generated once per azd environment.
    --web-auth-client-id <id> Microsoft Entra app registration client ID for the public web app.
    --web-auth-client-secret <value> Client secret for the existing app registration. Recommended.
    --web-auth-tenant-id <id> Microsoft Entra tenant ID for the public web app. Default: current tenant.
    --create-web-auth-app      Create a single-tenant workforce app registration before provisioning.
    --web-auth-app-name <val>  Display name for the created app registration. Default: derived from the web app.
        --function-auth-client-id <id> Microsoft Entra app registration client ID used to protect the Function App API.
        --function-auth-tenant-id <id> Microsoft Entra tenant ID for the Function App API. Default: current tenant.
        --create-function-auth-app   Create or reuse a single-tenant app registration for the Function App API.
        --function-auth-app-name <v> Display name for the Function App API registration. Default: derived from the Function App.
  --skip-code               Deploy infra only.
    --skip-provision          Skip the azd infrastructure provisioning step.
    --skip-web-deploy         Skip the App Service package deployment step.
    --prepare-only            Stop after preparing azd environment values and auth prerequisites.
  --skip-refresh            Skip the post-deploy refresh trigger.
  --use-prebuilt            Use pre-built artifacts from GHCR and GitHub Releases
                            instead of building locally. Requires gh CLI.
  --ghcr-image <ref>        Full GHCR image reference for the Function App container.
                            Default: ghcr.io/<repo-owner>/<repo-name>/function-app-container:latest
  --web-package-url <url>   URL to a pre-built web-package.zip. Default: latest
                            GitHub Release asset.
  --deployment-slot <name> Deployment target: qa, prod, or production.
                            prod promotes QA by swapping both app slots.
  --release-tag <tag>      Release identifier recorded on deployed QA artifacts.
  --help                    Show this help text.
EOF
}

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "Missing required command: $1" >&2
        exit 1
    fi
}

graph_auth_checked="false"
web_auth_app_created="false"
graph_cli_timeout_seconds="${GRAPH_CLI_TIMEOUT_SECONDS:-60}"

is_graph_interaction_required_error() {
    local error_file="$1"

    [[ -f "$error_file" ]] || return 1
    grep -Eq 'InteractionRequired|TokenCreatedWithOutdatedPolicies|Continuous access evaluation resulted in challenge' "$error_file"
}

run_graph_cli() {
    local stdout_file stderr_file exit_code
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    if timeout "${graph_cli_timeout_seconds}s" az "$@" >"$stdout_file" 2>"$stderr_file"; then
        cat "$stdout_file"
        rm -f "$stdout_file" "$stderr_file"
        return 0
    fi

    exit_code=$?

    if is_graph_interaction_required_error "$stderr_file"; then
        echo "Microsoft Graph access requires refreshed Azure CLI credentials. Run 'az login --scope https://graph.microsoft.com/.default' or 'azd auth login' in this shell, then retry." >&2
    fi

    if [[ $exit_code -eq 124 ]]; then
        echo "Timed out waiting for Azure CLI Microsoft Graph command: az $*" >&2
    fi

    cat "$stderr_file" >&2
    rm -f "$stdout_file" "$stderr_file"
    return "$exit_code"
}

ensure_graph_access() {
    local stdout_file stderr_file

    if [[ "$graph_auth_checked" == "true" ]]; then
        return 0
    fi

    graph_auth_checked="true"
    stdout_file="$(mktemp)"
    stderr_file="$(mktemp)"

    if timeout "${graph_cli_timeout_seconds}s" az account get-access-token --resource-type ms-graph --query accessToken -o tsv >"$stdout_file" 2>"$stderr_file"; then
        rm -f "$stdout_file" "$stderr_file"
        return 0
    fi

    if ! timeout "${graph_cli_timeout_seconds}s" az account get-access-token --resource-type ms-graph --query accessToken -o tsv >"$stdout_file" 2>"$stderr_file"; then
        echo "Unable to acquire a Microsoft Graph access token for deployment automation." >&2
        if is_graph_interaction_required_error "$stderr_file"; then
            echo "Azure CLI authentication is present, but Microsoft Graph requires refreshed credentials. Run 'az login --scope https://graph.microsoft.com/.default' or 'azd auth login' in this shell, then retry." >&2
        fi
        if [[ $? -eq 124 ]]; then
            echo "Timed out waiting for Azure CLI to acquire a Microsoft Graph token." >&2
        fi
        cat "$stderr_file" >&2
        rm -f "$stdout_file" "$stderr_file"
        return 1
    fi

    rm -f "$stdout_file" "$stderr_file"
}

resolve_signed_in_object_id() {
    local principal_type
    local principal_name

    principal_type="$(az account show --query 'user.type' -o tsv 2>/dev/null || true)"
    principal_name="$(az account show --query 'user.name' -o tsv 2>/dev/null || true)"

    case "$principal_type" in
        user)
            az ad signed-in-user show --query id -o tsv 2>/dev/null || true
            ;;
        servicePrincipal)
            az ad sp show --id "$principal_name" --query id -o tsv 2>/dev/null || true
            ;;
        *)
            return 0
            ;;
    esac
}

ensure_blob_upload_access() {
    local rg_name="$1"
    local account_name="$2"
    local principal_id
    local principal_type
    local storage_scope
    local existing_assignment

    principal_id="$(resolve_signed_in_object_id)"
    principal_type="$(az account show --query 'user.type' -o tsv 2>/dev/null || true)"

    if [[ -z "$principal_id" || -z "$principal_type" ]]; then
        return 0
    fi

    storage_scope="$(az storage account show --resource-group "$rg_name" --name "$account_name" --query id -o tsv)"
    existing_assignment="$(az role assignment list \
        --scope "$storage_scope" \
        --assignee-object-id "$principal_id" \
        --query "[?roleDefinitionName=='Storage Blob Data Contributor'] | [0].id" \
        -o tsv 2>/dev/null || true)"

    if [[ -n "$existing_assignment" ]]; then
        return 0
    fi

    echo "Granting Blob upload access on deployment storage"
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "$principal_type" \
        --role "Storage Blob Data Contributor" \
        --scope "$storage_scope" \
        --only-show-errors >/dev/null
}

ensure_subscription_reader_access() {
    local subscription_id="$1"
    local principal_id="${2:-}"
    local existing_assignment

    if [[ -z "$principal_id" || "$principal_id" == "null" ]]; then
        echo "Warning: could not resolve Function App principal ID for subscription Reader assignment" >&2
        return 0
    fi

    existing_assignment="$(az role assignment list \
        --scope "/subscriptions/${subscription_id}" \
        --assignee-object-id "$principal_id" \
        --query "[?roleDefinitionName=='Reader'] | [0].id" \
        -o tsv 2>/dev/null || true)"

    if [[ -n "$existing_assignment" ]]; then
        return 0
    fi

    echo "Granting subscription Reader access to Function App identity"
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role Reader \
        --scope "/subscriptions/${subscription_id}" \
        --only-show-errors >/dev/null
}

ensure_acr_push_access() {
    local rg_name="$1"
    local registry_name="$2"
    local principal_id
    local principal_type
    local registry_scope
    local existing_assignment

    principal_id="$(resolve_signed_in_object_id)"
    principal_type="$(az account show --query 'user.type' -o tsv 2>/dev/null || true)"

    if [[ -z "$principal_id" || -z "$principal_type" ]]; then
        return 0
    fi

    registry_scope="$(az acr show --resource-group "$rg_name" --name "$registry_name" --query id -o tsv)"
    existing_assignment="$(az role assignment list \
        --scope "$registry_scope" \
        --assignee-object-id "$principal_id" \
        --query "[?roleDefinitionName=='AcrPush'] | [0].id" \
        -o tsv 2>/dev/null || true)"

    if [[ -n "$existing_assignment" ]]; then
        return 0
    fi

    echo "Granting ACR push access on container registry"
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type "$principal_type" \
        --role AcrPush \
        --scope "$registry_scope" \
        --only-show-errors >/dev/null
}

ensure_deployment_blob_reader_access() {
    local rg_name="$1"
    local function_app_name="$2"
    local account_name="$3"
    local principal_id
    local storage_scope
    local existing_assignment

    principal_id="$(az functionapp identity show \
        --resource-group "$rg_name" \
        --name "$function_app_name" \
        --query principalId -o tsv 2>/dev/null || true)"

    if [[ -z "$principal_id" || "$principal_id" == "null" ]]; then
        echo "Warning: could not resolve Function App principal ID for deployment storage reader assignment" >&2
        return 0
    fi

    storage_scope="$(az storage account show --resource-group "$rg_name" --name "$account_name" --query id -o tsv)"
    existing_assignment="$(az role assignment list \
        --scope "$storage_scope" \
        --assignee-object-id "$principal_id" \
        --query "[?roleDefinitionName=='Storage Blob Data Reader'] | [0].id" \
        -o tsv 2>/dev/null || true)"

    if [[ -n "$existing_assignment" ]]; then
        return 0
    fi

    echo "Granting deployment package Blob read access to Function App identity"
    az role assignment create \
        --assignee-object-id "$principal_id" \
        --assignee-principal-type ServicePrincipal \
        --role "Storage Blob Data Reader" \
        --scope "$storage_scope" \
        --only-show-errors >/dev/null
}

resolve_existing_app_object_id() {
    local app_id="$1"

    ensure_graph_access >/dev/null 2>&1 || true
    run_graph_cli ad app show --id "$app_id" --query id -o tsv 2>/dev/null || true
}

resolve_app_id_by_display_name() {
    local display_name="$1"

    ensure_graph_access >/dev/null 2>&1 || true
    run_graph_cli ad app list --display-name "$display_name" --query '[0].appId' -o tsv 2>/dev/null || true
}

clean_tsv_value() {
    local value="${1:-}"

    if [[ -z "$value" || "$value" == "null" ]]; then
        printf ''
        return 0
    fi

    printf '%s' "$value"
}

create_or_reuse_web_auth_app_registration() {
    local display_name="$1"
    local sign_in_audience="AzureADMyOrg"
    local existing_app_id

    existing_app_id="$(resolve_app_id_by_display_name "$display_name")"
    if [[ -n "$existing_app_id" && "$existing_app_id" != "null" ]]; then
        web_auth_app_created="false"
        echo "$existing_app_id"
        return 0
    fi

    web_auth_app_created="true"
    ensure_graph_access >/dev/null
    run_graph_cli ad app create \
        --display-name "$display_name" \
        --sign-in-audience "$sign_in_audience" \
        --enable-id-token-issuance true \
        --query appId -o tsv
}

discover_existing_site_name_by_tag() {
    local rg_name="$1"
    local service_tag="$2"

    clean_tsv_value "$(az resource list \
        --resource-group "$rg_name" \
        --resource-type Microsoft.Web/sites \
        --tag azd-service-name="$service_tag" \
        --query '[0].name' -o tsv 2>/dev/null || true)"
}

discover_existing_site_name_by_prefix() {
    local rg_name="$1"
    local name_prefix_filter="$2"

    clean_tsv_value "$(az resource list \
        --resource-group "$rg_name" \
        --resource-type Microsoft.Web/sites \
        --query "[?starts_with(name, '${name_prefix_filter}')].name | [0]" -o tsv 2>/dev/null || true)"
}

extract_site_suffix_from_name() {
    local site_name="$1"
    local prefix="$2"
    local env_label="$3"
    local site_kind="$4"

    if [[ "$site_name" =~ ^${prefix}-${env_label}-${site_kind}-([a-z0-9]{4})$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
        return 0
    fi

    printf ''
}

discover_existing_site_suffix() {
    local rg_name="$1"
    local prefix="$2"
    local env_label="$3"
    local site_name=""
    local discovered_suffix=""

    site_name="$(discover_existing_site_name_by_tag "$rg_name" api)"
    discovered_suffix="$(extract_site_suffix_from_name "$site_name" "$prefix" "$env_label" func)"
    if [[ -n "$discovered_suffix" ]]; then
        printf '%s' "$discovered_suffix"
        return 0
    fi

    site_name="$(discover_existing_site_name_by_tag "$rg_name" web)"
    discovered_suffix="$(extract_site_suffix_from_name "$site_name" "$prefix" "$env_label" web)"
    if [[ -n "$discovered_suffix" ]]; then
        printf '%s' "$discovered_suffix"
        return 0
    fi

    printf ''
}

discover_existing_function_app_name() {
    local rg_name="$1"
    local prefix="$2"
    local env_label="$3"
    local current_suffix="$4"
    local expected_name=""
    local discovered_name=""

    if [[ -n "$current_suffix" ]]; then
        expected_name="${prefix}-${env_label}-func-${current_suffix}"
        discovered_name="$(clean_tsv_value "$(az functionapp show --resource-group "$rg_name" --name "$expected_name" --query name -o tsv 2>/dev/null || true)")"
        if [[ -n "$discovered_name" ]]; then
            printf '%s' "$discovered_name"
            return 0
        fi
    fi

    discovered_name="$(discover_existing_site_name_by_tag "$rg_name" api)"
    if [[ -n "$discovered_name" ]]; then
        printf '%s' "$discovered_name"
        return 0
    fi

    discover_existing_site_name_by_prefix "$rg_name" "${prefix}-${env_label}-func"
}

discover_existing_web_app_name() {
    local rg_name="$1"
    local prefix="$2"
    local env_label="$3"
    local current_suffix="$4"
    local expected_name=""
    local discovered_name=""

    if [[ -n "$current_suffix" ]]; then
        expected_name="${prefix}-${env_label}-web-${current_suffix}"
        discovered_name="$(clean_tsv_value "$(az webapp show --resource-group "$rg_name" --name "$expected_name" --query name -o tsv 2>/dev/null || true)")"
        if [[ -n "$discovered_name" ]]; then
            printf '%s' "$discovered_name"
            return 0
        fi
    fi

    discovered_name="$(discover_existing_site_name_by_tag "$rg_name" web)"
    if [[ -n "$discovered_name" ]]; then
        printf '%s' "$discovered_name"
        return 0
    fi

    discover_existing_site_name_by_prefix "$rg_name" "${prefix}-${env_label}-web"
}

discover_existing_site_url() {
    local rg_name="$1"
    local site_name="$2"
    local default_host_name=""

    if [[ -z "$site_name" ]]; then
        printf ''
        return 0
    fi

    default_host_name="$(clean_tsv_value "$(az resource show \
        --resource-group "$rg_name" \
        --resource-type Microsoft.Web/sites \
        --name "$site_name" \
        --query properties.defaultHostName -o tsv 2>/dev/null || true)")"

    if [[ -n "$default_host_name" ]]; then
        printf 'https://%s' "$default_host_name"
        return 0
    fi

    printf ''
}

discover_existing_site_auth_client_id() {
    local subscription_id="$1"
    local rg_name="$2"
    local site_name="$3"

    if [[ -z "$site_name" ]]; then
        printf ''
        return 0
    fi

    clean_tsv_value "$(az rest \
        --method GET \
        --url "$(build_arm_url "$(get_arm_endpoint_for_cloud "$(get_active_azure_cloud_name)")" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${site_name}/config/authsettingsV2?api-version=2022-09-01")" \
        --query 'properties.identityProviders.azureActiveDirectory.registration.clientId' -o tsv 2>/dev/null || true)"
}

discover_existing_container_registry_name() {
    local rg_name="$1"

    clean_tsv_value "$(az acr list --resource-group "$rg_name" --query '[0].name' -o tsv 2>/dev/null || true)"
}

discover_existing_virtual_network_name() {
    local rg_name="$1"
    local prefix="$2"
    local env_label="$3"
    local expected_name="${prefix}-${env_label}-vnet"
    local discovered_name=""

    discovered_name="$(clean_tsv_value "$(az network vnet show --resource-group "$rg_name" --name "$expected_name" --query name -o tsv 2>/dev/null || true)")"
    if [[ -n "$discovered_name" ]]; then
        printf '%s' "$discovered_name"
        return 0
    fi

    clean_tsv_value "$(az network vnet list --resource-group "$rg_name" --query '[0].name' -o tsv 2>/dev/null || true)"
}

discover_existing_function_uami_principal_id() {
    local rg_name="$1"
    local function_name="$2"

    if [[ -z "$function_name" ]]; then
        printf ''
        return 0
    fi

    clean_tsv_value "$(az resource show \
        --resource-group "$rg_name" \
        --resource-type Microsoft.ManagedIdentity/userAssignedIdentities \
        --name "${function_name}-uami" \
        --query properties.principalId -o tsv 2>/dev/null || true)"
}

safe_refresh_azd_environment() {
    echo "Refreshing azd environment outputs"
    if azd env refresh --no-prompt; then
        return 0
    fi

    echo "Warning: azd env refresh failed; continuing with live resource discovery fallback" >&2
    return 1
}

set_azd_env_value_if_present() {
    local key="$1"
    local value="${2:-}"

    if [[ -z "$value" ]]; then
        return 0
    fi

    azd env set "$key" "$value" >/dev/null
}

ensure_slot_diagnostics() {
    local resource_id="$1"
    local setting_name="$2"
    local workspace_id="$3"

    if [[ -z "$resource_id" || -z "$workspace_id" ]]; then
        return 0
    fi

    az monitor diagnostic-settings create \
        --name "$setting_name" \
        --resource "$resource_id" \
        --workspace "$workspace_id" \
        --logs '[{"categoryGroup":"allLogs","enabled":true}]' \
        --metrics '[{"category":"AllMetrics","enabled":true}]' \
        --only-show-errors \
        >/dev/null
}

sync_web_slot_access_restrictions() {
    local subscription_id="$1"
    local rg_name="$2"
    local web_name="$3"
    local arm_endpoint="$4"
    local production_config slot_config

    production_config="$(az rest --method get \
        --uri "$(build_arm_url "$arm_endpoint" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${web_name}/config/web?api-version=2024-04-01")")"
    slot_config="$(jq -c '{
        properties: {
            ipSecurityRestrictions: (.properties.ipSecurityRestrictions // []),
            scmIpSecurityRestrictions: (.properties.scmIpSecurityRestrictions // []),
            ipSecurityRestrictionsDefaultAction: (.properties.ipSecurityRestrictionsDefaultAction // "Allow"),
            scmIpSecurityRestrictionsDefaultAction: (.properties.scmIpSecurityRestrictionsDefaultAction // "Allow"),
            scmIpSecurityRestrictionsUseMain: (.properties.scmIpSecurityRestrictionsUseMain // false)
        }
    }' <<< "$production_config")"

    az rest --method patch \
        --uri "$(build_arm_url "$arm_endpoint" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${web_name}/slots/qa/config/web?api-version=2024-04-01")" \
        --body "$slot_config" \
        >/dev/null
}

ensure_qa_slots() {
    local rg_name="$1"
    local web_name="$2"
    local function_name="$3"
    local virtual_network_id="$4"
    local web_subnet_name="$5"
    local function_subnet_name="$6"
    local function_uami_id="$7"
    local workspace_id="$8"
    local web_slot_id function_slot_id
    local web_slot_subnet_id function_slot_subnet_id
    local -a function_slot_identities

    if ! deployment_slot_exists webapp "$rg_name" "$web_name"; then
        echo "Creating Web App QA slot"
        az webapp deployment slot create \
            --resource-group "$rg_name" \
            --name "$web_name" \
            --slot qa \
            --configuration-source "$web_name" \
            --only-show-errors \
            >/dev/null
    fi

    if ! deployment_slot_exists functionapp "$rg_name" "$function_name"; then
        echo "Creating Function App QA slot"
        az functionapp deployment slot create \
            --resource-group "$rg_name" \
            --name "$function_name" \
            --slot qa \
            --configuration-source "$function_name" \
            --only-show-errors \
            >/dev/null
    fi

    az webapp identity assign \
        --resource-group "$rg_name" \
        --name "$web_name" \
        --slot qa \
        --identities '[system]' \
        --only-show-errors \
        >/dev/null

    function_slot_identities=('[system]')
    if [[ -n "$function_uami_id" ]]; then
        function_slot_identities+=("$function_uami_id")
    fi
    az functionapp identity assign \
        --resource-group "$rg_name" \
        --name "$function_name" \
        --slot qa \
        --identities "${function_slot_identities[@]}" \
        --only-show-errors \
        >/dev/null

    web_slot_subnet_id="$(az webapp show \
        --resource-group "$rg_name" --name "$web_name" --slot qa \
        --query virtualNetworkSubnetId -o tsv 2>/dev/null || true)"
    if [[ -z "$web_slot_subnet_id" && -n "$virtual_network_id" && -n "$web_subnet_name" ]]; then
        az webapp vnet-integration add \
            --resource-group "$rg_name" \
            --name "$web_name" \
            --slot qa \
            --vnet "$virtual_network_id" \
            --subnet "$web_subnet_name" \
            --only-show-errors \
            >/dev/null
    fi
    function_slot_subnet_id="$(az functionapp show \
        --resource-group "$rg_name" --name "$function_name" --slot qa \
        --query virtualNetworkSubnetId -o tsv 2>/dev/null || true)"
    if [[ -z "$function_slot_subnet_id" && -n "$virtual_network_id" && -n "$function_subnet_name" ]]; then
        az functionapp vnet-integration add \
            --resource-group "$rg_name" \
            --name "$function_name" \
            --slot qa \
            --vnet "$virtual_network_id" \
            --subnet "$function_subnet_name" \
            --only-show-errors \
            >/dev/null
    fi

    web_slot_id="$(az webapp show --resource-group "$rg_name" --name "$web_name" --slot qa --query id -o tsv)"
    function_slot_id="$(az functionapp show --resource-group "$rg_name" --name "$function_name" --slot qa --query id -o tsv)"
    ensure_slot_diagnostics "$web_slot_id" "${web_name}-qa-diagnostics" "$workspace_id"
    ensure_slot_diagnostics "$function_slot_id" "${function_name}-qa-diagnostics" "$workspace_id"
}

deployment_slot_exists() {
    local app_kind="$1"
    local rg_name="$2"
    local app_name="$3"
    local attempt

    for attempt in 1 2 3 4 5; do
        if az "$app_kind" show \
            --resource-group "$rg_name" \
            --name "$app_name" \
            --slot qa \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 5
    done

    return 1
}

wait_for_web_app_ready() {
    local web_url="$1"
    local attempts="${2:-90}"
    local delay_seconds="${3:-10}"
    local attempt=1
    local status_code=""

    if [[ -z "$web_url" ]]; then
        echo "Warning: web app URL is empty; skipping readiness check" >&2
        return 0
    fi

    while (( attempt <= attempts )); do
        status_code="$(curl -k -I -L -s -o /dev/null -w '%{http_code}' "$web_url" || true)"
        case "$status_code" in
            200|204|301|302|307|308|401|403)
                echo "Web app responded with HTTP ${status_code}; treating deployment as ready"
                return 0
                ;;
        esac

        echo "Waiting for web app readiness (${attempt}/${attempts}); last status: ${status_code:-curl_failed}"
        sleep "$delay_seconds"
        ((attempt += 1))
    done

    echo "Web app did not become ready after ${attempts} attempts. Last HTTP status: ${status_code:-curl_failed}" >&2
    return 1
}

deploy_web_package() {
    local rg_name="$1"
    local app_name="$2"
    local package_path="$3"
    local slot_name="$4"
    local attempt
    local -a slot_args=()

    if [[ "$slot_name" != "production" ]]; then
        slot_args=(--slot "$slot_name")
    fi

    for attempt in 1 2 3; do
        if az webapp deploy \
            --resource-group "$rg_name" \
            --name "$app_name" \
            "${slot_args[@]}" \
            --src-path "$package_path" \
            --type zip \
            --clean true \
            --restart true \
            --track-status false \
            >/dev/null; then
            return 0
        fi

        if (( attempt < 3 )); then
            echo "Web package deployment attempt ${attempt}/3 failed; restarting ${slot_name} and retrying" >&2
            az webapp restart \
                --resource-group "$rg_name" \
                --name "$app_name" \
                "${slot_args[@]}" \
                >/dev/null 2>&1 || true
            sleep 20
        fi
    done

    echo "Web package deployment failed after 3 attempts for slot ${slot_name}" >&2
    return 1
}

wait_for_web_api_health() {
    local web_url="$1"
    local attempts="${2:-30}"
    local delay_seconds="${3:-10}"
    local attempt status_code

    for ((attempt = 1; attempt <= attempts; attempt++)); do
        status_code="$(curl -k -s -o /dev/null -w '%{http_code}' --max-time 30 "${web_url}/api/health" || true)"
        if [[ "$status_code" == "200" ]]; then
            echo "Web API health check passed: ${web_url}/api/health"
            return 0
        fi
        echo "Waiting for Web API health (${attempt}/${attempts}); last status: ${status_code:-curl_failed}"
        sleep "$delay_seconds"
    done

    echo "Web API health check failed for ${web_url}/api/health" >&2
    return 1
}

create_web_auth_app_registration() {
    local display_name="$1"
    local sign_in_audience="AzureADMyOrg"

    az ad app create \
        --display-name "$display_name" \
        --sign-in-audience "$sign_in_audience" \
        --enable-id-token-issuance true \
        --query appId -o tsv
}

ensure_function_auth_identifier_uri() {
    local app_id="$1"

    if [[ -z "$app_id" || "$app_id" == "null" ]]; then
        return 1
    fi

    ensure_graph_access >/dev/null
    run_graph_cli ad app update \
        --id "$app_id" \
        --identifier-uris "api://${app_id}" \
        --only-show-errors >/dev/null
}

create_function_auth_app_registration() {
    local display_name="$1"
    local sign_in_audience="AzureADMyOrg"
    local existing_app_id
    local app_id

    existing_app_id="$(resolve_app_id_by_display_name "$display_name")"
    if [[ -n "$existing_app_id" && "$existing_app_id" != "null" ]]; then
        ensure_function_auth_identifier_uri "$existing_app_id"
        echo "$existing_app_id"
        return 0
    fi

    ensure_graph_access >/dev/null
    app_id="$(run_graph_cli ad app create \
        --display-name "$display_name" \
        --sign-in-audience "$sign_in_audience" \
        --query appId -o tsv)"

    ensure_function_auth_identifier_uri "$app_id"
    echo "$app_id"
}

reset_web_auth_app_secret() {
    local app_id="$1"

    ensure_graph_access >/dev/null
    run_graph_cli ad app credential reset \
        --id "$app_id" \
        --append \
        --display-name "app-service-auth" \
        -o json | jq -r '.password // .secretText // empty'
}

sync_web_auth_app_registration() {
    local app_id="$1"
    local web_app_url="$2"

    if [[ -z "$app_id" || -z "$web_app_url" ]]; then
        return 0
    fi

    local app_object_id app_json callback_uri root_uri patch_body
    ensure_graph_access >/dev/null || return 1
    app_object_id="$(run_graph_cli ad app show --id "$app_id" --query 'id' -o tsv 2>/dev/null || true)"

    if [[ -z "$app_object_id" || "$app_object_id" == "null" ]]; then
        return 1
    fi

    app_json="$(run_graph_cli ad app show --id "$app_id" --query '{web:web}' -o json 2>/dev/null || echo '{}')"
    callback_uri="${web_app_url}/.auth/login/aad/callback"
    root_uri="${web_app_url}/"

    patch_body="$(jq -cn \
        --argjson app "$app_json" \
        --arg homepage "$web_app_url" \
        --arg root "$root_uri" \
        --arg callback "$callback_uri" '
        ($app.web // {}) as $web |
        {
          web: ($web + {
            homePageUrl: $homepage,
            redirectUris: ((($web.redirectUris // []) + [$root, $callback])
              | map(select(type == "string" and length > 0))
              | unique),
            implicitGrantSettings: (($web.implicitGrantSettings // {}) + {
              enableIdTokenIssuance: true
            })
          })
        }
    ')"

    run_graph_cli rest \
        --method PATCH \
        --url "https://graph.microsoft.com/v1.0/applications/${app_object_id}" \
        --headers Content-Type=application/json \
        --body "$patch_body" \
        --only-show-errors >/dev/null

    run_graph_cli ad app show --id "$app_id" \
        --query "web.redirectUris[?@=='${callback_uri}'] | length(@)" \
        -o tsv 2>/dev/null | grep -qx '1'

    run_graph_cli ad app show --id "$app_id" \
        --query 'web.implicitGrantSettings.enableIdTokenIssuance' \
        -o tsv 2>/dev/null | grep -q '^true$'
}

set_web_auth_secret_setting() {
    local rg_name="$1"
    local web_name="$2"
    local client_secret="$3"
    local slot_name="${4:-production}"
    local -a slot_args=()

    if [[ -z "$client_secret" ]]; then
        return 0
    fi
    if [[ "$slot_name" != "production" ]]; then
        slot_args+=(--slot "$slot_name")
    fi

    az webapp config appsettings set \
        --resource-group "$rg_name" \
        --name "$web_name" \
        "${slot_args[@]}" \
        --settings MICROSOFT_PROVIDER_AUTHENTICATION_SECRET="$client_secret" \
        >/dev/null
}

sync_function_app_auth_authorization_policy() {
        local subscription_id="$1"
        local rg_name="$2"
        local function_name="$3"
        local slot_name="$4"
        shift 4
        local auth_url
        local identities_json
        local applications_json='[]'
        local auth_settings_json
        local patch_body
        local allowed_identity
        local allowed_application

        if [[ $# -eq 0 ]]; then
                return 0
        fi

        local slot_path=""
        if [[ -n "$slot_name" && "$slot_name" != "production" ]]; then
                slot_path="/slots/${slot_name}"
        fi
        auth_url="$(build_arm_url "$(get_arm_endpoint_for_cloud "$(get_active_azure_cloud_name)")" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${function_name}${slot_path}/config/authsettingsV2?api-version=2022-09-01")"
        identities_json="$(printf '%s\n' "$@" | awk 'NF' | jq -R . | jq -s 'unique')"

        while IFS= read -r allowed_identity; do
                allowed_application="$(az ad sp show --id "$allowed_identity" --query appId -o tsv 2>/dev/null || true)"
                if [[ -n "$allowed_application" && "$allowed_application" != "null" ]]; then
                        applications_json="$(jq -cn \
                                --argjson applications "$applications_json" \
                                --arg application "$allowed_application" \
                                '($applications + [$application]) | map(select(type == "string" and length > 0)) | unique')"
                fi
        done < <(printf '%s\n' "$@" | awk 'NF')

        auth_settings_json="$(az rest --method GET --url "$auth_url" -o json 2>/dev/null || echo '{}')"

        patch_body="$(jq -cn \
                --argjson auth "$auth_settings_json" \
                --argjson identities "$identities_json" \
                --argjson applications "$applications_json" '
                ($auth.properties // {}) as $properties |
                ($properties.identityProviders // {}) as $identityProviders |
                ($identityProviders.azureActiveDirectory // {}) as $aad |
                ($aad.validation // {}) as $validation |
                {
                    properties: ($properties + {
                        identityProviders: ($identityProviders + {
                            azureActiveDirectory: ($aad + {
                                validation: ($validation + {
                                    defaultAuthorizationPolicy: ((($validation.defaultAuthorizationPolicy // {}) + {
                                        allowedApplications: (((($validation.defaultAuthorizationPolicy.allowedApplications // []) + $applications)
                                            | map(select(type == "string" and length > 0))
                                            | unique)),
                                        allowedPrincipals: (((($validation.defaultAuthorizationPolicy.allowedPrincipals // {}) + {
                                            identities: $identities
                                        })))
                                    }))
                                })
                            })
                        })
                    })
                }
        ')"

        az rest \
                --method PUT \
                --url "$auth_url" \
                --headers Content-Type=application/json \
                --body "$patch_body" \
                --only-show-errors >/dev/null

        for allowed_identity in "$@"; do
                az rest --method GET --url "$auth_url" \
                        --query "properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedPrincipals.identities[?@=='${allowed_identity}'] | length(@)" \
                        -o tsv 2>/dev/null | grep -qx '1'
        done

        while IFS= read -r allowed_application; do
                [[ -z "$allowed_application" ]] && continue
                az rest --method GET --url "$auth_url" \
                        --query "properties.identityProviders.azureActiveDirectory.validation.defaultAuthorizationPolicy.allowedApplications[?@=='${allowed_application}'] | length(@)" \
                        -o tsv 2>/dev/null | grep -qx '1'
        done < <(jq -r '.[]' <<<"$applications_json")
}

get_function_api_access_token() {
        local resource_uri="$1"

        if [[ -z "$resource_uri" ]]; then
                return 0
        fi

        az account get-access-token \
                --resource "$resource_uri" \
                --query accessToken -o tsv 2>/dev/null || true
}

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-*//; s/-*$//'
}

normalize_site_suffix() {
    local suffix="${1:-}"

    suffix="$(printf '%s' "$suffix" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')"
    printf '%s' "${suffix:0:4}"
}

generate_site_suffix() {
    python3 -c "import secrets, string; alphabet = string.ascii_lowercase + string.digits; print(''.join(secrets.choice(alphabet) for _ in range(4)))"
}

resolve_location() {
    local rg_name="$1"
    local explicit_location="$2"
    local cli_default_location=""

    if [[ -n "$explicit_location" ]]; then
        echo "$explicit_location"
        return 0
    fi

    if [[ "$(az group exists --name "$rg_name" -o tsv 2>/dev/null || echo false)" == "true" ]]; then
        az group show --name "$rg_name" --query location -o tsv
        return 0
    fi

    cli_default_location="$(az config get defaults.location --query value -o tsv 2>/dev/null || true)"
    if [[ -n "$cli_default_location" ]]; then
        echo "$cli_default_location"
        return 0
    fi

    echo "eastus"
}

get_active_azure_cloud_name() {
    local cloud_name
    cloud_name="$(az cloud show --query name -o tsv 2>/dev/null || true)"
    printf '%s' "${cloud_name:-AzureCloud}"
}

get_arm_endpoint_for_cloud() {
    local cloud_name="${1:-AzureCloud}"

    case "${cloud_name,,}" in
        azureusgovernment)
            printf '%s' 'https://management.usgovcloudapi.net'
            ;;
        *)
            printf '%s' 'https://management.azure.com'
            ;;
    esac
}

get_authority_host_for_cloud() {
    local cloud_name="${1:-AzureCloud}"

    case "${cloud_name,,}" in
        azureusgovernment)
            printf '%s' 'https://login.microsoftonline.us'
            ;;
        *)
            printf '%s' 'https://login.microsoftonline.com'
            ;;
    esac
}

build_arm_url() {
    local arm_endpoint="$1"
    local path="$2"

    if [[ "$path" != /* ]]; then
        path="/${path}"
    fi

    printf '%s' "${arm_endpoint%/}${path}"
}

is_us_gov_region() {
    local region_name="${1,,}"
    [[ "$region_name" == usgov* || "$region_name" == usdod* ]]
}

normalize_region_key() {
        local value="${1,,}"
        printf '%s' "$value" | tr -cd '[:alnum:]'
}

provider_resource_availability_status() {
        local namespace="$1"
        local resource_type_candidates="$2"
        local region_name="$3"
        local provider_json=""
        local normalized_region_name=""
        local resource_type=""
        local status="missing-resource-type"

        provider_json="$(az provider show -n "$namespace" --expand "resourceTypes/locations" -o json 2>/dev/null || true)"
        if [[ -z "$provider_json" ]]; then
                printf '%s' 'missing-provider'
                return 0
        fi

        normalized_region_name="$(normalize_region_key "$region_name")"

        IFS=',' read -r -a resource_type_list <<< "$resource_type_candidates"
        for resource_type in "${resource_type_list[@]}"; do
                status="$(jq -r \
                        --arg resourceType "$resource_type" \
                        --arg regionName "$normalized_region_name" '
                        [
                            .resourceTypes[]?
                            | select((.resourceType // "" | ascii_downcase) == ($resourceType | ascii_downcase))
                        ] as $matches
                        | if ($matches | length) == 0 then
                                "missing-resource-type"
                            elif ([
                                $matches[]
                                | (.locations // [])[]?
                                | ascii_downcase
                                | gsub("[^a-z0-9]"; "")
                                | select(. == $regionName)
                            ] | length) > 0 then
                                "available"
                            elif ([
                                $matches[]
                                | (.locations // [])
                                | length
                            ] | add) == 0 then
                                "global-or-unscoped"
                            else
                                "unavailable"
                            end
                        ' <<<"$provider_json" 2>/dev/null || printf '%s' 'unknown')"

                if [[ "$status" == 'available' || "$status" == 'global-or-unscoped' || "$status" == 'unavailable' || "$status" == 'unknown' ]]; then
                        printf '%s' "$status"
                        return 0
                fi
        done

        printf '%s' "$status"
}

write_service_availability_report() {
        local cloud_name="$1"
        local report_path="$2"
        local results_json="$3"
        local failed_count="$4"

        mkdir -p "$(dirname "$report_path")"
        jq -cn \
                --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
                --arg cloud "$cloud_name" \
                --argjson checks "$results_json" \
                --argjson failedCount "$failed_count" '
                {
                    generatedAt: $generatedAt,
                    cloud: $cloud,
                    failedCount: $failedCount,
                    checks: $checks
                }
                ' > "$report_path"
}

validate_current_services_availability() {
        local cloud_name="$1"
        local deployment_region="$2"
        local source_region_name="$3"
        local target_region_name="$4"
        local report_path="$5"
        local checks=(
                "deployment|App Service site hosting|Microsoft.Web|sites|$deployment_region"
                "deployment|App Service plan hosting|Microsoft.Web|serverfarms,sites|$deployment_region"
                "deployment|Function App hosting|Microsoft.Web|sites|$deployment_region"
                "deployment|Storage account|Microsoft.Storage|storageAccounts|$deployment_region"
                "deployment|Container registry|Microsoft.ContainerRegistry|registries|$deployment_region"
                "deployment|Application Insights|Microsoft.Insights|components|$deployment_region"
                "deployment|Virtual network|Microsoft.Network|virtualNetworks|$deployment_region"
                "deployment|Private endpoint|Microsoft.Network|privateEndpoints|$deployment_region"
                "deployment|User assigned identity|Microsoft.ManagedIdentity|userAssignedIdentities|$deployment_region"
                "analysis-source|VM availability checks|Microsoft.Compute|virtualMachines|$source_region_name"
                "analysis-target|VM availability checks|Microsoft.Compute|virtualMachines|$target_region_name"
                "analysis-source|Storage availability checks|Microsoft.Storage|storageAccounts|$source_region_name"
                "analysis-target|Storage availability checks|Microsoft.Storage|storageAccounts|$target_region_name"
        )
        local entry
        local check_scope
        local description
        local namespace
        local resource_type
        local region_name
        local status
        local available
        local results_json='[]'
        local failed_count=0

        for entry in "${checks[@]}"; do
                IFS='|' read -r check_scope description namespace resource_type region_name <<< "$entry"
                status="$(provider_resource_availability_status "$namespace" "$resource_type" "$region_name")"
                available='false'
                if [[ "$status" == 'available' || "$status" == 'global-or-unscoped' ]]; then
                        available='true'
                else
                        ((failed_count += 1))
                fi

                results_json="$(jq -cn \
                        --argjson current "$results_json" \
                        --arg scope "$check_scope" \
                        --arg description "$description" \
                        --arg namespace "$namespace" \
                        --arg resourceType "$resource_type" \
                        --arg region "$region_name" \
                        --arg status "$status" \
                        --argjson available "$available" '
                        $current + [{
                            scope: $scope,
                            description: $description,
                            providerNamespace: $namespace,
                            resourceType: $resourceType,
                            region: $region,
                            status: $status,
                            available: $available
                        }]
                        ')"
        done

        write_service_availability_report "$cloud_name" "$report_path" "$results_json" "$failed_count"
        echo "Service availability validation report written to $report_path"

        if [[ "$failed_count" -gt 0 ]]; then
                echo "Required hosted services are not available in one or more selected regions. Review $report_path before retrying." >&2
                exit 1
        fi
}

validate_cloud_region_alignment() {
    local cloud_name="$1"
    shift
    local region_name

    for region_name in "$@"; do
        [[ -z "$region_name" ]] && continue

        if [[ "${cloud_name,,}" == 'azureusgovernment' ]]; then
            if ! is_us_gov_region "$region_name"; then
                echo "AzureUSGovernment deployments only support Azure Government regions. Received region '$region_name'." >&2
                exit 1
            fi
            continue
        fi

        if is_us_gov_region "$region_name"; then
            echo "Region '$region_name' requires AzureUSGovernment. Run 'az cloud set --name AzureUSGovernment' and re-authenticate before retrying." >&2
            exit 1
        fi
    done
}

ensure_azd_environment() {
    local env_name="$1"
    local env_location="$2"
    local env_subscription="$3"

    if ! azd env list --output json | jq -e --arg env_name "$env_name" '.[] | select((.name // .Name) == $env_name)' >/dev/null; then
        if [[ -n "$env_subscription" ]]; then
            azd env new "$env_name" --location "$env_location" --subscription "$env_subscription" --no-prompt >/dev/null
        else
            azd env new "$env_name" --location "$env_location" --no-prompt >/dev/null
        fi
    fi

    azd env select "$env_name" >/dev/null
}

get_optional_azd_env_value() {
    local key="$1"
    local output=""

    if output="$(azd env get-value "$key" 2>/dev/null)"; then
        printf '%s' "$output"
        return 0
    fi

    printf ''
}

build_web_deployment_package() {
    local project_root="$1"
    local package_root="$project_root/.deploy/web"
    local package_file="$project_root/.deploy/web-package.zip"
    local generated_root="$project_root/data/generated"
    local package_generated_root="$package_root/data/generated"
    local package_lock_file="$project_root/web_app/package-lock.json"
    local package_manifest_file="$project_root/web_app/package.json"
    local server_file="$project_root/web_app/server.js"
    local web_source_dir="$project_root/web_app/src"
    local build_output_dir="$project_root/web_app/dist"
    local npm_install_stamp="$project_root/web_app/node_modules/.aca-install-stamp"
    local artifact_file

    if [[ -f "$package_file" ]] \
        && [[ ! "$server_file" -nt "$package_file" ]] \
        && [[ ! "$package_manifest_file" -nt "$package_file" ]] \
        && [[ ! "$package_lock_file" -nt "$package_file" ]] \
        && [[ -d "$web_source_dir" ]] \
        && ! find "$web_source_dir" -type f -newer "$package_file" | grep -q . \
        && [[ ! -d "$generated_root" || ! $(find "$generated_root" -maxdepth 1 -type f \( -name 'feature_catalog.snapshot.json' -o -name 'feature_catalog.db' -o -name 'canonical_service_identity.snapshot.json' -o -name 'canonical_identity_gaps.snapshot.json' \) -newer "$package_file" -print -quit) ]]; then
        printf '%s' "$package_file"
        return 0
    fi

    rm -rf "$package_root" "$package_file"
    mkdir -p "$package_root"

    if [[ -f "$project_root/data/feature_catalog/services.json" ]] && command -v python3 >/dev/null 2>&1; then
        (
            cd "$project_root"
            if [[ ! -f data/generated/feature_catalog.snapshot.json ]] \
                || [[ data/feature_catalog/services.json -nt data/generated/feature_catalog.snapshot.json ]] \
                || [[ ! -f data/generated/feature_catalog.db ]] \
                || [[ data/feature_catalog/services.json -nt data/generated/feature_catalog.db ]] \
                || [[ ! -f data/generated/canonical_service_identity.snapshot.json ]] \
                || [[ data/feature_catalog/services.json -nt data/generated/canonical_service_identity.snapshot.json ]]; then
                PYTHONPATH="$project_root/src${PYTHONPATH:+:$PYTHONPATH}" \
                    python3 -m azure_compare_cli build-catalog \
                    --source data/feature_catalog/services.json \
                    --output-json data/generated/feature_catalog.snapshot.json \
                    --output-sqlite data/generated/feature_catalog.db \
                    --output-identity-json data/generated/canonical_service_identity.snapshot.json >&2
            fi
        )
    fi

    if [[ ! -d "$project_root/web_app/node_modules" ]] || [[ ! -f "$npm_install_stamp" ]] || [[ "$package_lock_file" -nt "$npm_install_stamp" ]] || [[ "$package_manifest_file" -nt "$npm_install_stamp" ]]; then
        (
            cd "$project_root/web_app"
            npm ci --ignore-scripts >&2
            mkdir -p node_modules
            touch "$npm_install_stamp"
        )
    fi

    if [[ ! -d "$build_output_dir" ]] || [[ "$server_file" -nt "$build_output_dir/index.html" ]] || [[ "$package_manifest_file" -nt "$build_output_dir/index.html" ]] || [[ "$package_lock_file" -nt "$build_output_dir/index.html" ]] || find "$web_source_dir" -type f -newer "$build_output_dir/index.html" | grep -q .; then
        (
            cd "$project_root/web_app"
            npm run build >&2
        )
    fi

    cp "$project_root/web_app/server.js" "$package_root/server.js"
    cp -R "$project_root/web_app/dist" "$package_root/dist"

    if [[ -d "$generated_root" ]]; then
        mkdir -p "$package_generated_root"
        for artifact in \
            feature_catalog.snapshot.json \
            feature_catalog.db \
            canonical_service_identity.snapshot.json \
            canonical_identity_gaps.snapshot.json; do
            artifact_file="$generated_root/$artifact"
            if [[ -f "$artifact_file" ]]; then
                cp "$artifact_file" "$package_generated_root/$artifact"
            fi
        done
    fi

    cat > "$package_root/package.json" <<'EOF'
{
    "name": "azure-comparative-regional-analysis-web-runtime",
    "version": "0.1.0",
    "private": true,
    "description": "Runtime package for the Azure regional analysis web app",
    "engines": {
        "node": ">=22.12.0"
    },
    "scripts": {
        "start": "node server.js"
    },
    "dependencies": {
        "@azure/identity": "^4.13.1",
        "express": "^5.2.1"
    }
}
EOF

    (
        cd "$package_root"
        npm install --omit=dev --ignore-scripts --no-package-lock --engine-strict >&2
    )

    (
        cd "$package_root"
        zip -qr "$package_file" .
    )

    if [[ ! -f "$package_file" ]]; then
        echo "Web deployment package was not created: $package_file" >&2
        return 1
    fi

    printf '%s' "$package_file"
}

ensure_resource_group() {
    local rg_name="$1"
    local rg_location="$2"

    if [[ "$(az group exists --name "$rg_name" -o tsv 2>/dev/null || echo false)" == "true" ]]; then
        return 0
    fi

    echo "Creating resource group: $rg_name ($rg_location)"
    az group create --name "$rg_name" --location "$rg_location" --only-show-errors -o none
}

discover_expected_function_names() {
    local function_root="$1"

    find "$function_root" -mindepth 2 -maxdepth 2 -name function.json -exec dirname {} \; \
        | xargs -r -n1 basename \
        | sort -u
}

sync_function_triggers() {
    local subscription_id="$1"
    local rg_name="$2"
    local app_name="$3"
    local slot_name="${4:-production}"
    local slot_path=""

    if [[ "$slot_name" != "production" ]]; then
        slot_path="/slots/${slot_name}"
    fi

    az rest --method post \
        --url "$(build_arm_url "$(get_arm_endpoint_for_cloud "$(get_active_azure_cloud_name)")" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${app_name}${slot_path}/syncfunctiontriggers?api-version=2024-04-01")" \
        >/dev/null
}

wait_for_function_image_config() {
    local rg_name="$1"
    local app_name="$2"
    local subscription_id="$3"
    local expected_image_reference="$4"
    local max_attempts="$5"
    local delay_seconds="$6"
    local slot_name="${7:-production}"
    local expected_linux_fx="DOCKER|${expected_image_reference}"
    local current_linux_fx=""
    local attempt
    local slot_path=""

    if [[ "$slot_name" != "production" ]]; then
        slot_path="/slots/${slot_name}"
    fi

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        current_linux_fx="$(az rest --method get \
            --uri "$(build_arm_url "$(get_arm_endpoint_for_cloud "$(get_active_azure_cloud_name)")" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${app_name}${slot_path}?api-version=2024-04-01")" \
            --query properties.siteConfig.linuxFxVersion -o tsv 2>/dev/null || true)"

        if [[ "$current_linux_fx" == "$expected_linux_fx" ]]; then
            return 0
        fi

        echo "Waiting for Function App image handoff (attempt ${attempt}/${max_attempts})" >&2
        sleep "$delay_seconds"
    done

    echo "Function App image handoff did not complete. Expected ${expected_linux_fx}, found ${current_linux_fx:-<empty>}" >&2
    return 1
}

wait_for_function_indexing() {
    local subscription_id="$1"
    local rg_name="$2"
    local app_name="$3"
    local max_attempts="$4"
    local delay_seconds="$5"
    local slot_name="$6"
    shift 6
    local -a expected_functions=("$@")
    local attempt
    local functions_json=""
    local expected_function
    local -a missing_functions=()
    local slot_path=""

    if [[ "$slot_name" != "production" ]]; then
        slot_path="/slots/${slot_name}"
    fi

    if [[ ${#expected_functions[@]} -eq 0 ]]; then
        echo "Warning: no expected functions were discovered for deployment verification" >&2
        return 0
    fi

    for ((attempt = 1; attempt <= max_attempts; attempt++)); do
        if functions_json="$(az rest --method get \
            --url "$(build_arm_url "$(get_arm_endpoint_for_cloud "$(get_active_azure_cloud_name)")" "/subscriptions/${subscription_id}/resourceGroups/${rg_name}/providers/Microsoft.Web/sites/${app_name}${slot_path}/functions?api-version=2024-04-01")" \
            --query value -o json 2>/dev/null)"; then
            missing_functions=()

            for expected_function in "${expected_functions[@]}"; do
                if ! jq -e --arg expected_function "$expected_function" \
                    'map(.name | split("/")[-1]) | index($expected_function)' \
                    >/dev/null <<<"$functions_json"; then
                    missing_functions+=("$expected_function")
                fi
            done

            if [[ ${#missing_functions[@]} -eq 0 ]]; then
                return 0
            fi

            echo "Waiting for Function App indexing (attempt ${attempt}/${max_attempts}); missing: ${missing_functions[*]}" >&2
        else
            echo "Waiting for Function App indexing (attempt ${attempt}/${max_attempts}); host not ready yet" >&2
        fi

        sync_function_triggers "$subscription_id" "$rg_name" "$app_name" >/dev/null 2>&1 || true
        sleep "$delay_seconds"
    done

    echo "Function App did not index the expected functions: ${expected_functions[*]}" >&2
    return 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

resource_group=""
environment_name=""
subscription=""
location=""
source_region=""
target_region=""
name_prefix="azcomparereg"
environment_label="dev"
site_suffix="${ANALYSIS_SITE_SUFFIX:-}"
web_auth_client_id="${WEB_AUTH_CLIENT_ID:-}"
web_auth_client_secret="${WEB_AUTH_CLIENT_SECRET:-}"
web_auth_tenant_id="${WEB_AUTH_TENANT_ID:-}"
create_web_auth_app="false"
web_auth_app_name=""
function_auth_client_id="${FUNCTION_AUTH_CLIENT_ID:-}"
function_auth_tenant_id="${FUNCTION_AUTH_TENANT_ID:-}"
create_function_auth_app="false"
function_auth_app_name=""
skip_code="false"
skip_provision="false"
skip_web_deploy="false"
prepare_only="false"
skip_refresh="false"
use_prebuilt="false"
ghcr_image=""
web_package_url=""
deployment_slot="production"
release_tag=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)
            resource_group="$2"
            shift 2
            ;;
        --environment-name)
            environment_name="$2"
            shift 2
            ;;
        --subscription)
            subscription="$2"
            shift 2
            ;;
        --location)
            location="$2"
            shift 2
            ;;
        --source-region)
            source_region="$2"
            shift 2
            ;;
        --target-region)
            target_region="$2"
            shift 2
            ;;
        --name-prefix)
            name_prefix="$2"
            shift 2
            ;;
        --environment-label)
            environment_label="$2"
            shift 2
            ;;
        --site-suffix)
            site_suffix="$2"
            shift 2
            ;;
        --web-auth-client-id)
            web_auth_client_id="$2"
            shift 2
            ;;
        --web-auth-client-secret)
            web_auth_client_secret="$2"
            shift 2
            ;;
        --web-auth-tenant-id)
            web_auth_tenant_id="$2"
            shift 2
            ;;
        --create-web-auth-app)
            create_web_auth_app="true"
            shift
            ;;
        --web-auth-app-name)
            web_auth_app_name="$2"
            shift 2
            ;;
        --function-auth-client-id)
            function_auth_client_id="$2"
            shift 2
            ;;
        --function-auth-tenant-id)
            function_auth_tenant_id="$2"
            shift 2
            ;;
        --create-function-auth-app)
            create_function_auth_app="true"
            shift
            ;;
        --function-auth-app-name)
            function_auth_app_name="$2"
            shift 2
            ;;
        --skip-code)
            skip_code="true"
            shift
            ;;
        --skip-provision)
            skip_provision="true"
            shift
            ;;
        --skip-web-deploy)
            skip_web_deploy="true"
            shift
            ;;
        --prepare-only)
            prepare_only="true"
            shift
            ;;
        --skip-refresh)
            skip_refresh="true"
            shift
            ;;
        --use-prebuilt)
            use_prebuilt="true"
            shift
            ;;
        --ghcr-image)
            ghcr_image="$2"
            shift 2
            ;;
        --web-package-url)
            web_package_url="$2"
            shift 2
            ;;
        --deployment-slot)
            deployment_slot="${2,,}"
            shift 2
            ;;
        --release-tag)
            release_tag="$2"
            shift 2
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$deployment_slot" != "production" && "$deployment_slot" != "qa" && "$deployment_slot" != "prod" ]]; then
    echo "--deployment-slot must be 'qa', 'prod', or 'production'." >&2
    exit 1
fi

if [[ -z "$resource_group" ]]; then
    echo "--resource-group is required." >&2
    usage >&2
    exit 1
fi

require_command az
require_command azd
require_command curl
require_command jq
require_command python3
require_command zip

cd "$PROJECT_ROOT"

mapfile -t expected_function_names < <(discover_expected_function_names "$PROJECT_ROOT/azure_pipeline/function_app")

function_image_verification_attempts=20
function_image_verification_delay_seconds=15

if [[ -n "$subscription" ]]; then
    az account set --subscription "$subscription"
fi

subscription_id="$(az account show --query id -o tsv)"
tenant_id="$(az account show --query tenantId -o tsv)"

if [[ -z "$web_auth_tenant_id" ]]; then
    web_auth_tenant_id="$tenant_id"
fi

if [[ -z "$function_auth_tenant_id" ]]; then
    function_auth_tenant_id="$tenant_id"
fi

if [[ -z "$environment_name" ]]; then
    environment_name="${AZURE_ENV_NAME:-}"
fi

if [[ -z "$environment_name" ]]; then
    environment_name="$(get_optional_azd_env_value AZURE_ENV_NAME)"
fi

if [[ -z "$environment_name" ]]; then
    environment_name="$(slugify "$resource_group")"
fi

resolved_location="$(resolve_location "$resource_group" "$location")"
active_cloud_name="$(get_active_azure_cloud_name)"
arm_endpoint="$(get_arm_endpoint_for_cloud "$active_cloud_name")"
authority_host="$(get_authority_host_for_cloud "$active_cloud_name")"

if [[ -z "$source_region" ]]; then
    source_region="$resolved_location"
fi

if [[ -z "$target_region" ]]; then
    if [[ "$source_region" == "eastus" ]]; then
        target_region="westus2"
    else
        target_region="eastus"
    fi
fi

validate_cloud_region_alignment "$active_cloud_name" "$resolved_location" "$source_region" "$target_region"
validation_report_path="$PROJECT_ROOT/output/service_validation_${active_cloud_name,,}_${resolved_location}.json"
validate_current_services_availability "$active_cloud_name" "$resolved_location" "$source_region" "$target_region" "$validation_report_path"

ensure_resource_group "$resource_group" "$resolved_location"

echo "Configuring azd environment: $environment_name"
ensure_azd_environment "$environment_name" "$resolved_location" "$subscription_id"

site_suffix="$(normalize_site_suffix "$site_suffix")"
if [[ -z "$site_suffix" ]]; then
    site_suffix="$(normalize_site_suffix "$(get_optional_azd_env_value ANALYSIS_SITE_SUFFIX)")"
fi
discovered_live_site_suffix="$(discover_existing_site_suffix "$resource_group" "$name_prefix" "$environment_label")"
if [[ -n "$site_suffix" && -n "$discovered_live_site_suffix" && "$site_suffix" != "$discovered_live_site_suffix" ]]; then
    echo "Detected live hosted resource suffix ${discovered_live_site_suffix}; replacing stale environment suffix ${site_suffix}"
    site_suffix="$discovered_live_site_suffix"
fi
if [[ -z "$site_suffix" ]]; then
    site_suffix="$discovered_live_site_suffix"
fi
if [[ -z "$site_suffix" ]]; then
    site_suffix="$(generate_site_suffix)"
fi

provisional_function_app_name="$(discover_existing_function_app_name "$resource_group" "$name_prefix" "$environment_label" "$site_suffix")"
if [[ -z "$provisional_function_app_name" ]]; then
    provisional_function_app_name="${name_prefix}-${environment_label}-func-${site_suffix}"
fi

provisional_web_app_name="$(discover_existing_web_app_name "$resource_group" "$name_prefix" "$environment_label" "$site_suffix")"
if [[ -z "$provisional_web_app_name" ]]; then
    provisional_web_app_name="${name_prefix}-${environment_label}-web-${site_suffix}"
fi

resolved_live_site_suffix="$(extract_site_suffix_from_name "$provisional_function_app_name" "$name_prefix" "$environment_label" func)"
if [[ -z "$resolved_live_site_suffix" ]]; then
    resolved_live_site_suffix="$(extract_site_suffix_from_name "$provisional_web_app_name" "$name_prefix" "$environment_label" web)"
fi
if [[ -n "$resolved_live_site_suffix" && "$site_suffix" != "$resolved_live_site_suffix" ]]; then
    echo "Detected live hosted resource suffix ${resolved_live_site_suffix}; replacing stale environment suffix ${site_suffix}"
    site_suffix="$resolved_live_site_suffix"
    provisional_function_app_name="${name_prefix}-${environment_label}-func-${site_suffix}"
    provisional_web_app_name="${name_prefix}-${environment_label}-web-${site_suffix}"
fi

existing_function_container_image="$(az functionapp config show \
    --resource-group "$resource_group" \
    --name "$provisional_function_app_name" \
    --query linuxFxVersion -o tsv 2>/dev/null || true)"
existing_function_container_image="${existing_function_container_image#DOCKER|}"

if [[ -z "$web_auth_client_id" ]]; then
    web_auth_client_id="$(discover_existing_site_auth_client_id "$subscription_id" "$resource_group" "$provisional_web_app_name")"
fi

if [[ -z "$function_auth_client_id" ]]; then
    function_auth_client_id="$(discover_existing_site_auth_client_id "$subscription_id" "$resource_group" "$provisional_function_app_name")"
fi

if [[ -z "$web_auth_app_name" ]]; then
    web_auth_app_name="${name_prefix}-${environment_label}-${site_suffix}-web-auth"
fi

if [[ -z "$function_auth_app_name" ]]; then
    function_auth_app_name="${name_prefix}-${environment_label}-${site_suffix}-func-auth"
fi

if [[ "$create_web_auth_app" == "true" ]]; then
    if [[ -z "$web_auth_client_id" ]]; then
        echo "Creating or reusing Microsoft Entra app registration: $web_auth_app_name"
        web_auth_client_id="$(create_or_reuse_web_auth_app_registration "$web_auth_app_name")"
    else
        echo "Using provided Microsoft Entra app registration client ID: $web_auth_client_id"
    fi

    if [[ -z "$web_auth_client_secret" && "$web_auth_app_created" == "true" ]]; then
        echo "Creating client secret for Microsoft Entra app registration"
        web_auth_client_secret="$(reset_web_auth_app_secret "$web_auth_client_id")"
    fi
fi

if [[ -z "$web_auth_client_id" || "$web_auth_client_id" == "__ip_restrict__" ]]; then
    if [[ "$web_auth_client_id" == "__ip_restrict__" ]]; then
        echo "IP-restriction mode: skipping Microsoft Entra app registration requirement"
    else
        echo "Either --web-auth-client-id or --create-web-auth-app is required." >&2
        usage >&2
        exit 1
    fi
fi

if [[ -z "$function_auth_client_id" ]]; then
    function_auth_client_id="$(get_optional_azd_env_value FUNCTION_AUTH_CLIENT_ID)"
fi

if [[ -z "$function_auth_tenant_id" ]]; then
    function_auth_tenant_id="$(get_optional_azd_env_value FUNCTION_AUTH_TENANT_ID)"
fi

if [[ "$create_function_auth_app" == "true" || -z "$function_auth_client_id" ]]; then
    if [[ -z "$function_auth_client_id" ]]; then
        echo "Creating Microsoft Entra app registration for the Function App API: $function_auth_app_name"
        function_auth_client_id="$(create_function_auth_app_registration "$function_auth_app_name")"
    else
        echo "Using provided Function App API registration client ID: $function_auth_client_id"
        ensure_function_auth_identifier_uri "$function_auth_client_id"
    fi
else
    ensure_function_auth_identifier_uri "$function_auth_client_id"
fi

function_auth_resource=""
if [[ -n "$function_auth_client_id" ]]; then
    function_auth_resource="api://${function_auth_client_id}"
fi

azd env set AZURE_RESOURCE_GROUP "$resource_group" >/dev/null
azd env set AZURE_LOCATION "$resolved_location" >/dev/null
azd env set ANALYSIS_NAME_PREFIX "$name_prefix" >/dev/null
azd env set ANALYSIS_ENVIRONMENT "$environment_label" >/dev/null
azd env set ANALYSIS_SITE_SUFFIX "$site_suffix" >/dev/null
azd env set AZURE_SUBSCRIPTION_ID "$subscription_id" >/dev/null
azd env set AZURE_CLOUD_ENVIRONMENT "$active_cloud_name" >/dev/null
azd env set CLOUD_ENVIRONMENT "$active_cloud_name" >/dev/null
azd env set ARM_ENDPOINT "$arm_endpoint" >/dev/null
azd env set MANAGEMENT_SCOPE "${arm_endpoint}/.default" >/dev/null
azd env set AZURE_AUTHORITY_HOST "$authority_host" >/dev/null
azd env set ANALYSIS_SOURCE_REGION "$source_region" >/dev/null
azd env set ANALYSIS_TARGET_REGION "$target_region" >/dev/null
azd env set WEB_AUTH_CLIENT_ID "$web_auth_client_id" >/dev/null
azd env set WEB_AUTH_TENANT_ID "$web_auth_tenant_id" >/dev/null
azd env set FUNCTION_AUTH_CLIENT_ID "$function_auth_client_id" >/dev/null
azd env set FUNCTION_AUTH_TENANT_ID "$function_auth_tenant_id" >/dev/null
azd env set FUNCTION_CONTAINER_IMAGE "$existing_function_container_image" >/dev/null
if [[ -n "$web_auth_client_secret" ]]; then
    azd env set WEB_AUTH_CLIENT_SECRET_SETTING_NAME MICROSOFT_PROVIDER_AUTHENTICATION_SECRET >/dev/null
else
    azd env set WEB_AUTH_CLIENT_SECRET_SETTING_NAME '' >/dev/null
fi

if [[ "$prepare_only" == "true" ]]; then
    echo "Prepared azd environment and authentication prerequisites"
    exit 0
fi

if [[ "$skip_provision" == "false" ]]; then
    echo "Provisioning infrastructure with azd"
    azd provision --no-prompt
else
    echo "Skipping infrastructure provisioning"
fi

safe_refresh_azd_environment || true

function_app_name="$(get_optional_azd_env_value functionAppName)"
if [[ -z "$function_app_name" ]]; then
    function_app_name="$provisional_function_app_name"
fi
if [[ -z "$function_app_name" ]]; then
    function_app_name="${name_prefix}-${environment_label}-func-${site_suffix}"
fi

function_app_base_url="$(get_optional_azd_env_value functionAppBaseUrl)"
if [[ -z "$function_app_base_url" ]]; then
    function_app_base_url="$(discover_existing_site_url "$resource_group" "$function_app_name")"
fi
if [[ -z "$function_app_base_url" ]]; then
    function_app_base_url="https://${function_app_name}.azurewebsites.net"
fi

function_uami_principal_id="$(get_optional_azd_env_value functionAppUserAssignedPrincipalId)"
if [[ -z "$function_uami_principal_id" ]]; then
    function_uami_principal_id="$(discover_existing_function_uami_principal_id "$resource_group" "$function_app_name")"
fi
ensure_subscription_reader_access "$subscription_id" "$function_uami_principal_id"

web_app_name="$(get_optional_azd_env_value webAppName)"
if [[ -z "$web_app_name" ]]; then
    web_app_name="$provisional_web_app_name"
fi
if [[ -z "$web_app_name" ]]; then
    web_app_name="${name_prefix}-${environment_label}-web-${site_suffix}"
fi

web_app_url="$(get_optional_azd_env_value webAppUrl)"
if [[ -z "$web_app_url" ]]; then
    web_app_url="$(discover_existing_site_url "$resource_group" "$web_app_name")"
fi
if [[ -z "$web_app_url" && -n "$web_app_name" ]]; then
    web_app_url="https://${web_app_name}.azurewebsites.net"
fi

virtual_network_name="$(get_optional_azd_env_value virtualNetworkName)"
if [[ -z "$virtual_network_name" ]]; then
    virtual_network_name="$(discover_existing_virtual_network_name "$resource_group" "$name_prefix" "$environment_label")"
fi

target_slot_name="production"
web_slot_args=()
function_slot_args=()
target_web_app_url="$web_app_url"
target_function_app_base_url="$function_app_base_url"

if [[ "$deployment_slot" == "qa" || "$deployment_slot" == "prod" ]]; then
    virtual_network_id="$(az network vnet show \
        --resource-group "$resource_group" \
        --name "$virtual_network_name" \
        --query id -o tsv 2>/dev/null || true)"
    function_uami_id="$(az identity show \
        --resource-group "$resource_group" \
        --name "${function_app_name}-uami" \
        --query id -o tsv 2>/dev/null || true)"
    log_analytics_workspace_id="$(get_optional_azd_env_value logAnalyticsWorkspaceId)"

    if [[ "$deployment_slot" == "prod" ]]; then
        if ! deployment_slot_exists webapp "$resource_group" "$web_app_name" \
            || ! deployment_slot_exists functionapp "$resource_group" "$function_app_name"; then
            echo "QA slots are missing or unavailable; deploy to QA before production promotion." >&2
            exit 1
        fi
    else
        ensure_qa_slots \
            "$resource_group" \
            "$web_app_name" \
            "$function_app_name" \
            "$virtual_network_id" \
            web-integration \
            functions-integration \
            "$function_uami_id" \
            "$log_analytics_workspace_id"
    fi
    sync_web_slot_access_restrictions \
        "$subscription_id" \
        "$resource_group" \
        "$web_app_name" \
        "$arm_endpoint"

    qa_function_url="https://${function_app_name}-qa.azurewebsites.net"
    qa_web_url="https://${web_app_name}-qa.azurewebsites.net"

    az webapp config appsettings set \
        --resource-group "$resource_group" \
        --name "$web_app_name" \
        --slot-settings FUNCTION_BASE_URL="$function_app_base_url" DEPLOYMENT_SLOT=prod \
        >/dev/null
    az webapp config appsettings set \
        --resource-group "$resource_group" \
        --name "$web_app_name" \
        --slot qa \
        --slot-settings FUNCTION_BASE_URL="$qa_function_url" DEPLOYMENT_SLOT=qa \
        >/dev/null

    az webapp config appsettings set \
        --resource-group "$resource_group" \
        --name "$function_app_name" \
        --slot-settings \
            COMPARISON_TABLE_NAME=CurrentComparisons \
            RUNS_TABLE_NAME=RefreshRuns \
            DETAILS_CONTAINER_NAME=comparison-details \
            PRICING_CONTAINER_NAME=pricing-cache \
            AzureWebJobs.scheduled_refresh.Disabled=false \
            DEPLOYMENT_SLOT=prod \
        >/dev/null
    az webapp config appsettings set \
        --resource-group "$resource_group" \
        --name "$function_app_name" \
        --slot qa \
        --slot-settings \
            COMPARISON_TABLE_NAME=CurrentComparisonsQa \
            RUNS_TABLE_NAME=RefreshRunsQa \
            DETAILS_CONTAINER_NAME=comparison-details-qa \
            PRICING_CONTAINER_NAME=pricing-cache-qa \
            AzureWebJobs.scheduled_refresh.Disabled=true \
            DEPLOYMENT_SLOT=qa \
        >/dev/null

    if [[ "$deployment_slot" == "prod" ]]; then
        production_release_tag="$(az webapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            --query "[?name=='DEPLOYED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        if [[ -z "$production_release_tag" ]]; then
            production_release_tag="pre-slot-production-$(date -u +%Y%m%dt%H%M%Sz)"
            az webapp config appsettings set \
                --resource-group "$resource_group" \
                --name "$web_app_name" \
                --settings DEPLOYED_RELEASE_TAG="$production_release_tag" \
                >/dev/null
        fi
        az webapp config appsettings set \
            --resource-group "$resource_group" \
            --name "$function_app_name" \
            --settings DEPLOYED_RELEASE_TAG="$production_release_tag" \
            >/dev/null

        qa_release_tag="$(az webapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            --slot qa \
            --query "[?name=='DEPLOYED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        qa_web_validated_tag="$(az webapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            --slot qa \
            --query "[?name=='QA_VALIDATED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        qa_function_release_tag="$(az webapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$function_app_name" \
            --slot qa \
            --query "[?name=='DEPLOYED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        qa_function_validated_tag="$(az webapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$function_app_name" \
            --slot qa \
            --query "[?name=='QA_VALIDATED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        if [[ -z "$qa_release_tag" \
            || "$qa_web_validated_tag" != "$qa_release_tag" \
            || "$qa_function_release_tag" != "$qa_release_tag" \
            || "$qa_function_validated_tag" != "$qa_release_tag" ]]; then
            echo "QA release identity is incomplete or not validated. Redeploy QA before production promotion." >&2
            exit 1
        fi
        qa_function_image="$(az rest --method get \
            --uri "$(build_arm_url "$arm_endpoint" "/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${function_app_name}/slots/qa/config/web?api-version=2024-04-01")" \
            --query properties.linuxFxVersion -o tsv)"
        qa_function_image="${qa_function_image#DOCKER|}"

        echo "Validating QA release before production promotion: $qa_release_tag"
        wait_for_web_api_health "$qa_web_url"

        echo "Promoting Function App QA slot to production"
        if ! az functionapp deployment slot swap \
            --resource-group "$resource_group" \
            --name "$function_app_name" \
            --slot qa \
            --target-slot production \
            --only-show-errors \
            >/dev/null; then
            echo "Function App slot promotion failed; production was not changed." >&2
            exit 1
        fi

        echo "Promoting Web App QA slot to production"
        if ! az webapp deployment slot swap \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            --slot qa \
            --target-slot production \
            --only-show-errors \
            >/dev/null; then
            echo "Web App slot promotion failed; restoring the previous production Function slot." >&2
            az functionapp deployment slot swap \
                --resource-group "$resource_group" \
                --name "$function_app_name" \
                --slot qa \
                --target-slot production \
                --only-show-errors \
                >/dev/null || true
            exit 1
        fi

        promotion_healthy=true
        az functionapp restart \
            --resource-group "$resource_group" \
            --name "$function_app_name" \
            --slot qa \
            >/dev/null || promotion_healthy=false
        az webapp restart \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            --slot qa \
            >/dev/null || promotion_healthy=false
        wait_for_web_api_health "$qa_web_url" || promotion_healthy=false
        wait_for_web_api_health "$web_app_url" || promotion_healthy=false
        if [[ "$promotion_healthy" != "true" ]]; then
            echo "Post-promotion health validation failed; restoring the previous production slots." >&2
            az functionapp deployment slot swap \
                --resource-group "$resource_group" \
                --name "$function_app_name" \
                --slot qa \
                --target-slot production \
                --only-show-errors \
                >/dev/null || true
            az webapp deployment slot swap \
                --resource-group "$resource_group" \
                --name "$web_app_name" \
                --slot qa \
                --target-slot production \
                --only-show-errors \
                >/dev/null || true
            wait_for_web_api_health "$web_app_url" || true
            exit 1
        fi

        rollback_release_tag="$(az webapp config appsettings list \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            --slot qa \
            --query "[?name=='DEPLOYED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        if [[ -n "$rollback_release_tag" ]]; then
            az webapp config appsettings set \
                --resource-group "$resource_group" \
                --name "$web_app_name" \
                --slot qa \
                --settings QA_VALIDATED_RELEASE_TAG="$rollback_release_tag" \
                >/dev/null
            az webapp config appsettings set \
                --resource-group "$resource_group" \
                --name "$function_app_name" \
                --slot qa \
                --settings QA_VALIDATED_RELEASE_TAG="$rollback_release_tag" \
                >/dev/null
        fi
        azd env set FUNCTION_CONTAINER_IMAGE "$qa_function_image" >/dev/null
        echo "Promoted QA release to production: $qa_release_tag"
        exit 0
    fi

    target_slot_name="qa"
    web_slot_args=(--slot qa)
    function_slot_args=(--slot qa)
    target_web_app_url="$qa_web_url"
    target_function_app_base_url="$qa_function_url"
fi

if [[ -z "$web_auth_client_id" ]]; then
    web_auth_client_id="$(discover_existing_site_auth_client_id "$subscription_id" "$resource_group" "$web_app_name")"
fi

if [[ -z "$function_auth_client_id" ]]; then
    function_auth_client_id="$(discover_existing_site_auth_client_id "$subscription_id" "$resource_group" "$function_app_name")"
fi

set_azd_env_value_if_present ANALYSIS_SITE_SUFFIX "$site_suffix"
set_azd_env_value_if_present WEB_AUTH_CLIENT_ID "$web_auth_client_id"
set_azd_env_value_if_present FUNCTION_AUTH_CLIENT_ID "$function_auth_client_id"
set_azd_env_value_if_present functionAppName "$function_app_name"
set_azd_env_value_if_present functionAppBaseUrl "$function_app_base_url"
set_azd_env_value_if_present functionAppUserAssignedPrincipalId "$function_uami_principal_id"
set_azd_env_value_if_present webAppName "$web_app_name"
set_azd_env_value_if_present webAppUrl "$web_app_url"
set_azd_env_value_if_present virtualNetworkName "$virtual_network_name"

web_app_principal_id=""
if [[ -n "$web_app_name" ]]; then
    web_app_principal_id="$(az webapp identity show \
        --resource-group "$resource_group" \
        --name "$web_app_name" \
        "${web_slot_args[@]}" \
        --query principalId -o tsv 2>/dev/null || true)"
fi
deployer_principal_id="$(resolve_signed_in_object_id)"

function_auth_allowed_identities=()
if [[ -n "$web_app_principal_id" && "$web_app_principal_id" != "null" ]]; then
    function_auth_allowed_identities+=("$web_app_principal_id")
fi
if [[ -n "$deployer_principal_id" && "$deployer_principal_id" != "null" ]]; then
    function_auth_allowed_identities+=("$deployer_principal_id")
fi

if [[ -n "$function_auth_client_id" && ${#function_auth_allowed_identities[@]} -gt 0 ]]; then
    sync_function_app_auth_authorization_policy \
        "$subscription_id" \
        "$resource_group" \
        "$function_app_name" \
        "$target_slot_name" \
        "${function_auth_allowed_identities[@]}"
fi

if [[ -n "$web_app_name" && -n "$target_web_app_url" ]]; then
    if [[ "$web_auth_client_id" == "__ip_restrict__" ]]; then
        echo "IP-restriction mode: skipping Microsoft Entra redirect URI synchronization"
    elif sync_web_auth_app_registration "$web_auth_client_id" "$target_web_app_url"; then
        echo "Synced Microsoft Entra app registration redirect URIs"
    else
        echo "Warning: could not sync Microsoft Entra app registration redirect URIs; verify Graph permissions and update ${target_web_app_url}/.auth/login/aad/callback manually" >&2
    fi

    if [[ -n "$web_auth_client_secret" ]]; then
        set_web_auth_secret_setting "$resource_group" "$web_app_name" "$web_auth_client_secret" "$target_slot_name"
    fi

    if [[ "$skip_code" == "false" && "$skip_web_deploy" == "false" ]]; then
        if [[ "$use_prebuilt" == "true" ]]; then
            echo "Downloading pre-built web package from GitHub Releases"
            web_package_file="$PROJECT_ROOT/.deploy/web-package.zip"
            mkdir -p "$PROJECT_ROOT/.deploy"
            if [[ -n "$web_package_url" ]]; then
                curl -fsSL -o "$web_package_file" "$web_package_url"
            else
                # Download from the latest public GitHub Release (no auth required)
                repo_slug="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[:/](.+)(\.git)?$#\1#' | sed 's/\.git$//')"
                release_url="https://github.com/${repo_slug}/releases/latest/download/web-package.zip"
                echo "  Source: $release_url"
                if ! curl -fsSL -o "$web_package_file" "$release_url"; then
                    echo "Failed to download web-package.zip from: $release_url" >&2
                    echo "Ensure the build-artifacts workflow has run and the repo/release is public." >&2
                    exit 1
                fi
            fi
        else
            echo "Building App Service web frontend locally"
            if ! web_package_file="$(build_web_deployment_package "$PROJECT_ROOT")"; then
                echo "Failed to build the App Service deployment package" >&2
                exit 1
            fi
        fi

        if [[ -z "$web_package_file" || ! -f "$web_package_file" ]]; then
            echo "Expected App Service deployment package was not found: ${web_package_file:-<empty>}" >&2
            exit 1
        fi

        echo "Deploying App Service web frontend from package"
        deploy_web_package \
            "$resource_group" \
            "$web_app_name" \
            "$web_package_file" \
            "$target_slot_name"

        az webapp config set \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            "${web_slot_args[@]}" \
            --startup-file 'node server.js' \
            >/dev/null

        if [[ -n "$release_tag" ]]; then
            az webapp config appsettings set \
                --resource-group "$resource_group" \
                --name "$web_app_name" \
                "${web_slot_args[@]}" \
                --settings DEPLOYED_RELEASE_TAG="$release_tag" \
                >/dev/null
        fi

        wait_for_web_app_ready "$target_web_app_url"
    elif [[ "$skip_web_deploy" == "true" ]]; then
        echo "Skipping App Service web package deployment"
    fi
fi

echo "Infrastructure deployed. Function App: $function_app_name"

if [[ "$skip_code" == "false" ]]; then
    container_registry_name="$(get_optional_azd_env_value containerRegistryName)"
    container_registry_login_server="$(get_optional_azd_env_value containerRegistryLoginServer)"
    container_image_name="$(get_optional_azd_env_value containerImageName)"

    if [[ -z "$container_registry_name" ]]; then
        container_registry_name="$(discover_existing_container_registry_name "$resource_group")"
    fi
    if [[ -z "$container_registry_login_server" && -n "$container_registry_name" ]]; then
        container_registry_login_server="$(clean_tsv_value "$(az acr show --resource-group "$resource_group" --name "$container_registry_name" --query loginServer -o tsv 2>/dev/null || true)")"
    fi
    if [[ -z "$container_image_name" ]]; then
        container_image_name="function-app"
    fi

    set_azd_env_value_if_present containerRegistryName "$container_registry_name"
    set_azd_env_value_if_present containerRegistryLoginServer "$container_registry_login_server"
    set_azd_env_value_if_present containerImageName "$container_image_name"

    if [[ -z "$container_registry_name" || -z "$container_registry_login_server" || -z "$container_image_name" ]]; then
        echo "Missing container registry outputs from azd environment." >&2
        exit 1
    fi

    image_tag="$(date -u +%Y%m%dt%H%M%Sz)"
    image_reference="${container_registry_login_server}/${container_image_name}:${image_tag}"

    if [[ "$use_prebuilt" == "true" ]]; then
        # Import pre-built image from GHCR into the deployment ACR
        if [[ -z "$ghcr_image" ]]; then
            # Derive GHCR image from the git remote (GHCR requires lowercase)
            repo_slug="$(git -C "$PROJECT_ROOT" remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[:/](.+)(\.git)?$#\1#' | sed 's/\.git$//' | tr '[:upper:]' '[:lower:]')"
            ghcr_image="ghcr.io/${repo_slug}/function-app-container:latest"
        fi
        echo "Importing Function App container image from GHCR: $ghcr_image"
        az acr import \
            --name "$container_registry_name" \
            --source "$ghcr_image" \
            --image "${container_image_name}:${image_tag}" \
            --force
    else
        ensure_acr_push_access "$resource_group" "$container_registry_name"
        echo "Building and pushing Function App container image"
        az acr build \
            --registry "$container_registry_name" \
            --image "${container_image_name}:${image_tag}" \
            "$PROJECT_ROOT/azure_pipeline/function_app"
    fi

    echo "Configuring Function App to run from the container image"
    az webapp config appsettings delete \
        --resource-group "$resource_group" \
        --name "$function_app_name" \
        "${function_slot_args[@]}" \
        --setting-names WEBSITE_CONTENTAZUREFILECONNECTIONSTRING WEBSITE_CONTENTSHARE WEBSITE_RUN_FROM_PACKAGE WEBSITE_RUN_FROM_PACKAGE_BLOB_MI_RESOURCE_ID SCM_DO_BUILD_DURING_DEPLOYMENT ENABLE_ORYX_BUILD \
        >/dev/null 2>&1 || true

    az webapp config appsettings set \
        --resource-group "$resource_group" \
        --name "$function_app_name" \
        "${function_slot_args[@]}" \
        --settings DOCKER_REGISTRY_SERVER_URL="https://${container_registry_login_server}" WEBSITES_ENABLE_APP_SERVICE_STORAGE=false AZURE_CLOUD_ENVIRONMENT="$active_cloud_name" CLOUD_ENVIRONMENT="$active_cloud_name" ARM_ENDPOINT="$arm_endpoint" MANAGEMENT_SCOPE="${arm_endpoint}/.default" AZURE_AUTHORITY_HOST="$authority_host" ANALYSIS_SOURCE_REGION="$source_region" ANALYSIS_TARGET_REGION="$target_region" \
        1>/dev/null

    function_slot_path=""
    if [[ "$target_slot_name" != "production" ]]; then
        function_slot_path="/slots/${target_slot_name}"
    fi
    function_uami_client_id="$(get_optional_azd_env_value functionAppUserAssignedClientId)"
    function_site_config="$(jq -cn \
        --arg image "DOCKER|${image_reference}" \
        --arg acrIdentity "$function_uami_client_id" \
        '{linuxFxVersion: $image, acrUseManagedIdentityCreds: true, alwaysOn: true}
        + (if $acrIdentity == "" then {} else {acrUserManagedIdentityID: $acrIdentity} end)')"
    az rest --method patch \
        --uri "$(build_arm_url "$arm_endpoint" "/subscriptions/${subscription_id}/resourceGroups/${resource_group}/providers/Microsoft.Web/sites/${function_app_name}${function_slot_path}?api-version=2024-04-01")" \
        --body "$(jq -cn --argjson siteConfig "$function_site_config" '{properties:{siteConfig:$siteConfig}}')" \
        1>/dev/null

    if [[ -n "$release_tag" ]]; then
        az webapp config appsettings set \
            --resource-group "$resource_group" \
            --name "$function_app_name" \
            "${function_slot_args[@]}" \
            --settings DEPLOYED_RELEASE_TAG="$release_tag" \
            >/dev/null
    fi

    wait_for_function_image_config \
        "$resource_group" \
        "$function_app_name" \
        "$subscription_id" \
        "$image_reference" \
        "$function_image_verification_attempts" \
        "$function_image_verification_delay_seconds" \
        "$target_slot_name"

    az functionapp restart \
        --resource-group "$resource_group" \
        --name "$function_app_name" \
        "${function_slot_args[@]}"

    wait_for_function_image_config \
        "$resource_group" \
        "$function_app_name" \
        "$subscription_id" \
        "$image_reference" \
        "$function_image_verification_attempts" \
        "$function_image_verification_delay_seconds" \
        "$target_slot_name"

    sync_function_triggers "$subscription_id" "$resource_group" "$function_app_name" "$target_slot_name" >/dev/null 2>&1 || true

    wait_for_function_indexing \
        "$subscription_id" \
        "$resource_group" \
        "$function_app_name" \
        "$function_image_verification_attempts" \
        "$function_image_verification_delay_seconds" \
        "$target_slot_name" \
        "${expected_function_names[@]}"

    if [[ -n "$web_app_name" ]]; then
        echo "Configuring Web App proxy settings"
        az webapp config appsettings set \
            --resource-group "$resource_group" \
            --name "$web_app_name" \
            "${web_slot_args[@]}" \
            --settings FUNCTION_BASE_URL="$target_function_app_base_url" FUNCTION_AUTH_RESOURCE="$function_auth_resource" FUNCTION_API_KEY='' DEFAULT_SOURCE_REGION="$source_region" DEFAULT_TARGET_REGION="$target_region" AZURE_CLOUD_ENVIRONMENT="$active_cloud_name" CLOUD_ENVIRONMENT="$active_cloud_name" AZURE_AUTHORITY_HOST="$authority_host" \
            1>/dev/null
    fi

    if [[ "$target_slot_name" == "qa" ]]; then
        wait_for_web_api_health "$target_web_app_url"
        if [[ -n "$release_tag" ]]; then
            az webapp config appsettings set \
                --resource-group "$resource_group" \
                --name "$web_app_name" \
                --slot qa \
                --settings QA_VALIDATED_RELEASE_TAG="$release_tag" \
                >/dev/null
            az webapp config appsettings set \
                --resource-group "$resource_group" \
                --name "$function_app_name" \
                --slot qa \
                --settings QA_VALIDATED_RELEASE_TAG="$release_tag" \
                >/dev/null
        fi
    fi
fi

if [[ "$skip_code" == "false" && "$skip_refresh" == "false" && -n "$target_function_app_base_url" ]]; then
    echo "Attempting initial refresh"
    function_auth_access_token="$(get_function_api_access_token "$function_auth_resource")"
    if [[ -n "$function_auth_access_token" && "$function_auth_access_token" != "null" ]]; then
        refresh_payload="$(jq -cn \
            --arg sourceRegion "$source_region" \
            --arg targetRegion "$target_region" \
            --arg subscriptionId "$subscription_id" \
            --arg comparisonMode "inventory" \
            '{sourceRegion: $sourceRegion, targetRegion: $targetRegion, subscriptionId: $subscriptionId, comparisonMode: $comparisonMode}')"
        if refresh_response="$(curl -fsS -X POST \
            -H 'Content-Type: application/json' \
            -H "Authorization: Bearer ${function_auth_access_token}" \
            -d "$refresh_payload" \
            "${target_function_app_base_url}/api/refresh")"; then
            echo "Initial refresh completed successfully"
            echo "  Seed run       : $refresh_response"
        else
            echo "Warning: refresh trigger failed; deploy completed but no seed run was started" >&2
        fi
    else
        echo "Warning: no bearer token could be resolved for the initial refresh; deploy completed without seeding data" >&2
    fi
fi

echo
echo "Deployment complete"
echo "  Resource group : $resource_group"
echo "  Function app   : $function_app_name"
if [[ -n "$target_function_app_base_url" ]]; then
    echo "  Backend        : $target_function_app_base_url"
    echo "  Seed source    : $source_region"
    echo "  Seed target    : $target_region"
fi
if [[ -n "$target_web_app_url" ]]; then
    echo "  Web app        : $target_web_app_url"
fi
echo "  Deployment slot: $target_slot_name"
if [[ -n "${container_registry_login_server:-}" ]]; then
    echo "  Container image: ${container_registry_login_server}/${container_image_name}:${image_tag:-bootstrap}"
fi
if [[ -n "$virtual_network_name" ]]; then
    echo "  App VNet       : $virtual_network_name"
fi