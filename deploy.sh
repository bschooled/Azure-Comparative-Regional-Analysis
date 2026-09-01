#!/usr/bin/env bash
# ==============================================================================
# deploy.sh — One-command deployment wrapper for the Azure-hosted pipeline.
#
# Performs preflight checks, creates/selects an azd environment, and runs the
# full deployment with optional IP-restriction mode when Entra ID integrated
# auth is not desired.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Colours (disabled when stdout is not a TTY)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; BOLD=''; NC=''
fi

info()    { echo -e "${BLUE}[INFO]${NC}  $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC}    $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*" >&2; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

PROBE_FORBIDDEN_IPS=()
PROBE_LAST_STATUS=""
PROBE_ALLOWED_COUNT=0

probe_web_access() {
    local label="$1" client="$2" hostname="$3" samples="${4:-6}"
    local attempt response status forbidden_ip cache_buster
    local seen_ips=","

    PROBE_FORBIDDEN_IPS=()
    PROBE_LAST_STATUS=""
    PROBE_ALLOWED_COUNT=0

    for ((attempt = 1; attempt <= samples; attempt++)); do
        cache_buster="${label}-${attempt}-$(date +%s%N)"
        if [[ "$client" == "curl" ]]; then
            response="$(curl -sS -D - -o /dev/null --connect-timeout 10 --max-time 20 \
                "https://${hostname}/?ip-probe=${cache_buster}" 2>/dev/null || true)"
        else
            response="$("$client" -sS -D - -o NUL --connect-timeout 10 --max-time 20 \
                "https://${hostname}/?ip-probe=${cache_buster}" 2>/dev/null | tr -d '\r' || true)"
        fi

        status="$(printf '%s\n' "$response" | awk 'toupper($1) ~ /^HTTP\// {code=$2} END {print code}')"
        forbidden_ip="$(printf '%s\n' "$response" \
            | awk 'tolower($1) == "x-ms-forbidden-ip:" {print $2}' \
            | tr -d '\r' \
            | tail -1)"
        PROBE_LAST_STATUS="$status"

        if [[ "$status" == "200" || "$status" == "304" ]]; then
            ((PROBE_ALLOWED_COUNT += 1))
        fi

        if [[ "$status" == "403" && -n "$forbidden_ip" && "$seen_ips" != *",$forbidden_ip,"* ]]; then
            PROBE_FORBIDDEN_IPS+=("$forbidden_ip")
            seen_ips+="${forbidden_ip},"
        fi

        if (( ${#PROBE_FORBIDDEN_IPS[@]} > 1 )); then
            break
        fi
    done

    if (( ${#PROBE_FORBIDDEN_IPS[@]} > 1 || (PROBE_ALLOWED_COUNT > 0 && ${#PROBE_FORBIDDEN_IPS[@]} > 0) )); then
        error "$label traffic uses rotating source IPs: ${PROBE_FORBIDDEN_IPS[*]}"
        if (( PROBE_ALLOWED_COUNT > 0 )); then
            error "$label traffic also used an existing allowed source during the same probe."
        fi
        error "IP restriction cannot be reliable until the VPN egress uses a fixed public IP."
        error "Configure a NAT Gateway/Azure Firewall static egress IP, pass it with --allow-ip,"
        error "or deploy without --ip-restrict and use Entra ID authentication."
        return 2
    fi

    if [[ "$PROBE_LAST_STATUS" != "200" && "$PROBE_LAST_STATUS" != "304" && ${#PROBE_FORBIDDEN_IPS[@]} -eq 0 ]]; then
        error "$label access verification failed with HTTP ${PROBE_LAST_STATUS:-unknown}."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
RESOURCE_GROUP=""
LOCATION=""
SUBSCRIPTION=""
ENVIRONMENT_NAME=""
USE_IP_RESTRICTION="false"
ALLOWED_IPS=""
SKIP_PROVISION="false"
SKIP_REFRESH="false"
USE_PREBUILT="false"
GHCR_IMAGE=""
WEB_PACKAGE_URL=""
UPGRADE="false"
ACCESS_MODE_EXPLICIT="false"
DEPLOYMENT_SLOT="qa"
RELEASE_TAG=""
EXTRA_DEPLOY_ARGS=()

usage() {
    cat <<'EOF'
Usage: ./deploy.sh --resource-group <name> [options]

One-command deployment of the Azure-hosted regional analysis pipeline.

Required:
  --resource-group <name>      Target resource group.

Optional:
  --location <azure-region>    Deployment location (e.g., canadacentral).
  --subscription <id|name>     Azure subscription. Default: current account.
  --environment-name <name>    azd environment name. Default: derived from rg.
  --ip-restrict                Use Web App IP restriction instead of Entra ID
                               integrated auth. Requires a stable public egress
                               IP. WSL deployments also verify the Windows
                               browser path and reject rotating VPN egress.
  --allow-ip <cidr>            Additional IP or CIDR to allow (repeatable).
                               Implies --ip-restrict.
  --upgrade                    Upgrade an existing azd environment in place.
                               Uses immutable artifacts from the latest GitHub
                               release, provisions IaC unless --skip-provision,
                               preserves access rules, and skips data refresh.
  --slot <qa|prod>             Deployment target. Default: qa.
                               qa deploys a pinned release to validation slots;
                               prod promotes the currently validated QA slots.
  --release-tag <tag>          Exact GitHub release to deploy to QA. Production
                               promotion always uses the artifact already in QA.
  --skip-provision             Skip Bicep provisioning (code deploy only).
  --skip-refresh               Skip post-deploy comparison refresh.
  --use-prebuilt               Use pre-built artifacts from GHCR/GitHub Releases
                               instead of building locally. Requires gh CLI.
  --ghcr-image <ref>           Full GHCR image ref for Function App container.
  --web-package-url <url>      URL to pre-built web-package.zip.
  -h, --help                   Show this help.

Deployment Modes:
  Default             Entra ID integrated auth (requires an app registration).
  --ip-restrict       Web App is open to the internet but restricted to your
                      IP address (and any extras via --allow-ip). No Entra ID
                      app registration required. The Function App stays private
                      behind VNet integration and is never exposed to the
                      public internet.

Examples:
  # Standard Entra ID deployment
  ./deploy.sh --resource-group rg-analysis --location canadacentral

  # IP-restricted deployment (no Entra app required)
  ./deploy.sh --resource-group rg-analysis --location canadacentral --ip-restrict

  # IP-restricted with extra allowed range
  ./deploy.sh --resource-group rg-analysis --location canadacentral \
      --ip-restrict --allow-ip 203.0.113.0/24

  # Upgrade the QA slots from the latest successful release
  ./deploy.sh --resource-group rg-analysis \
      --environment-name rg-analysis --upgrade

  # Promote the validated QA slots to production
  ./deploy.sh --resource-group rg-analysis \
      --environment-name rg-analysis --upgrade --slot prod

  # Azure Government
  az cloud set --name AzureUSGovernment && az login
  ./deploy.sh --resource-group rg-analysis --location usgovvirginia --ip-restrict
EOF
    exit "${1:-0}"
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)   RESOURCE_GROUP="$2";    shift 2 ;;
        --location)         LOCATION="$2";          shift 2 ;;
        --subscription)     SUBSCRIPTION="$2";      shift 2 ;;
        --environment-name) ENVIRONMENT_NAME="$2";  shift 2 ;;
        --ip-restrict)      USE_IP_RESTRICTION="true"; ACCESS_MODE_EXPLICIT="true"; shift ;;
        --allow-ip)         ALLOWED_IPS="${ALLOWED_IPS:+${ALLOWED_IPS},}$2"
                            USE_IP_RESTRICTION="true"; ACCESS_MODE_EXPLICIT="true"; shift 2 ;;
        --upgrade)          UPGRADE="true"; USE_PREBUILT="true"; SKIP_REFRESH="true"; shift ;;
        --slot)             DEPLOYMENT_SLOT="${2,,}"; shift 2 ;;
        --release-tag)      RELEASE_TAG="$2"; USE_PREBUILT="true"; shift 2 ;;
        --skip-provision)   SKIP_PROVISION="true";  shift ;;
        --skip-refresh)     SKIP_REFRESH="true";    shift ;;
        --use-prebuilt)     USE_PREBUILT="true";    shift ;;
        --ghcr-image)       GHCR_IMAGE="$2";        shift 2 ;;
        --web-package-url)  WEB_PACKAGE_URL="$2";   shift 2 ;;
        -h|--help)          usage 0 ;;
        *)                  error "Unknown option: $1"; usage 1 ;;
    esac
done

if [[ -z "$RESOURCE_GROUP" ]]; then
    error "--resource-group is required."
    usage 1
fi

if [[ "$UPGRADE" == "true" && "$ACCESS_MODE_EXPLICIT" == "true" ]]; then
    error "--upgrade preserves the deployed access configuration and cannot be combined with --ip-restrict or --allow-ip."
    exit 1
fi

if [[ "$DEPLOYMENT_SLOT" != "qa" && "$DEPLOYMENT_SLOT" != "prod" ]]; then
    error "--slot must be either 'qa' or 'prod'."
    exit 1
fi

if [[ "$DEPLOYMENT_SLOT" == "prod" && -n "$RELEASE_TAG" ]]; then
    error "--release-tag applies only to QA deployments; production promotes the pinned QA release."
    exit 1
fi

if [[ "$DEPLOYMENT_SLOT" == "prod" ]]; then
    if [[ "$ACCESS_MODE_EXPLICIT" == "true" ]]; then
        error "--slot prod preserves the deployed access configuration and cannot change IP restrictions."
        exit 1
    fi
    UPGRADE="true"
    USE_PREBUILT="true"
    SKIP_REFRESH="true"
fi

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
preflight_ok=true

check_command() {
    local cmd="$1" purpose="$2"
    if command -v "$cmd" &>/dev/null; then
        success "$cmd found"
    else
        error "$cmd not found — $purpose"
        preflight_ok=false
    fi
}

info "Running preflight checks..."
check_command az      "Install Azure CLI: https://aka.ms/install-azure-cli"
check_command azd     "Install Azure Developer CLI: https://aka.ms/install-azd"
check_command jq      "Install jq: https://stedolan.github.io/jq/download/"
check_command curl    "Install curl from your package manager"
check_command python3 "Python 3 is required for the Function App build"
if [[ "$DEPLOYMENT_SLOT" == "prod" ]]; then
    :
elif [[ "$USE_PREBUILT" == "true" ]]; then
    check_command gh "Install GitHub CLI: https://cli.github.com/"
else
    check_command docker "Docker is required to build the Function App container image"
fi

# Check Bicep availability (bundled with az or standalone)
if az bicep version &>/dev/null; then
    success "Bicep available (via Azure CLI)"
elif command -v bicep &>/dev/null; then
    success "Bicep available (standalone)"
else
    warn "Bicep not found — attempting install via 'az bicep install'"
    az bicep install 2>/dev/null || { error "Bicep install failed"; preflight_ok=false; }
fi

# Azure login check
if az account show &>/dev/null; then
    account_name="$(az account show --query name -o tsv 2>/dev/null)"
    success "Logged in to Azure ($account_name)"
else
    error "Not logged in to Azure. Run 'az login' first."
    preflight_ok=false
fi

if [[ "$preflight_ok" != "true" ]]; then
    error "Preflight checks failed. Fix the issues above and retry."
    exit 1
fi

info "All preflight checks passed."

# ---------------------------------------------------------------------------
# Resolve subscription and cloud context
# ---------------------------------------------------------------------------
if [[ -n "$SUBSCRIPTION" ]]; then
    az account set --subscription "$SUBSCRIPTION"
fi

active_subscription="$(az account show --query id -o tsv)"
active_cloud="$(az cloud show --query name -o tsv 2>/dev/null || echo AzureCloud)"
info "Subscription : $active_subscription"
info "Cloud        : $active_cloud"

# ---------------------------------------------------------------------------
# azd environment setup
# ---------------------------------------------------------------------------
if [[ -z "$ENVIRONMENT_NAME" ]]; then
    ENVIRONMENT_NAME="${RESOURCE_GROUP}"
fi

info "azd environment: $ENVIRONMENT_NAME"

# Create or select the environment
if azd env list 2>/dev/null | grep -q "^${ENVIRONMENT_NAME}[[:space:]]"; then
    azd env select "$ENVIRONMENT_NAME"
    info "Selected existing azd environment '$ENVIRONMENT_NAME'"
elif [[ "$UPGRADE" == "true" ]]; then
    error "Upgrade requires existing azd environment '$ENVIRONMENT_NAME'."
    exit 1
else
    azd_new_args=("$ENVIRONMENT_NAME")
    if [[ -n "$LOCATION" ]]; then
        azd_new_args+=(--location "$LOCATION")
    fi
    azd_new_args+=(--subscription "$active_subscription")
    azd env new "${azd_new_args[@]}"
    success "Created azd environment '$ENVIRONMENT_NAME'"
fi

if [[ "$UPGRADE" == "true" ]]; then
    if [[ "$(az group exists --name "$RESOURCE_GROUP" -o tsv)" != "true" ]]; then
        error "Upgrade requires existing resource group '$RESOURCE_GROUP'."
        exit 1
    fi

    deployed_resource_group="$(azd env get-value AZURE_RESOURCE_GROUP 2>/dev/null || true)"
    if [[ -n "$deployed_resource_group" && "$deployed_resource_group" != "$RESOURCE_GROUP" ]]; then
        error "azd environment '$ENVIRONMENT_NAME' targets resource group '$deployed_resource_group', not '$RESOURCE_GROUP'."
        exit 1
    fi

    deployed_ip_mode="$(azd env get-value USE_IP_RESTRICTION 2>/dev/null || true)"
    if [[ "${deployed_ip_mode,,}" == "true" ]]; then
        USE_IP_RESTRICTION="true"
        EXTRA_DEPLOY_ARGS+=(--web-auth-client-id __ip_restrict__)
        info "Preserving existing IP-restriction mode and live access rules"
    else
        deployed_web_auth_client_id="$(azd env get-value WEB_AUTH_CLIENT_ID 2>/dev/null || true)"
        if [[ -z "$deployed_web_auth_client_id" || "$deployed_web_auth_client_id" == "__ip_restrict__" ]]; then
            error "Existing Entra deployment has no WEB_AUTH_CLIENT_ID in azd environment '$ENVIRONMENT_NAME'."
            exit 1
        fi
        EXTRA_DEPLOY_ARGS+=(--web-auth-client-id "$deployed_web_auth_client_id")
        info "Preserving existing Entra ID access mode"
    fi

fi

if [[ "$USE_PREBUILT" == "true" && "$DEPLOYMENT_SLOT" == "qa" ]]; then
    repo_slug="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null \
        | sed -E 's#.*github\.com[:/](.+)(\.git)?$#\1#' \
        | sed 's/\.git$//')"
    if [[ -n "$RELEASE_TAG" ]]; then
        release_json="$(gh release view "$RELEASE_TAG" --repo "$repo_slug" --json tagName,body 2>/dev/null || true)"
    else
        release_json="$(gh release view --repo "$repo_slug" --json tagName,body 2>/dev/null || true)"
    fi
    release_tag="$(jq -r '.tagName // empty' <<< "$release_json")"
    GHCR_IMAGE="$(jq -r '.body // "" | capture("Function App container: `(?<ref>[^`]+)`").ref // empty' <<< "$release_json" 2>/dev/null || true)"
    if [[ -z "$release_tag" || -z "$GHCR_IMAGE" ]]; then
        error "Could not resolve immutable deployment artifacts from the latest GitHub release."
        exit 1
    fi
    if [[ "$GHCR_IMAGE" == *":latest" ]]; then
        release_commit="${release_tag##*-}"
        GHCR_IMAGE="${GHCR_IMAGE%:*}:${release_commit}"
    fi
    GHCR_IMAGE="${GHCR_IMAGE,,}"
    WEB_PACKAGE_URL="https://github.com/${repo_slug}/releases/download/${release_tag}/web-package.zip"
    RELEASE_TAG="$release_tag"
    info "QA release: $RELEASE_TAG"
    info "Function image: $GHCR_IMAGE"
fi

azd env set AZURE_RESOURCE_GROUP "$RESOURCE_GROUP" >/dev/null

# ---------------------------------------------------------------------------
# Detect deployer IP for new IP-restriction deployments
# ---------------------------------------------------------------------------
deployer_ip=""
if [[ "$USE_IP_RESTRICTION" == "true" && "$UPGRADE" != "true" ]]; then
    info "Detecting your public IP address..."
    deployer_ip="$(curl -s --max-time 10 https://api.ipify.org 2>/dev/null || \
                   curl -s --max-time 10 https://ifconfig.me 2>/dev/null || true)"
    if [[ -z "$deployer_ip" ]]; then
        error "Could not detect your public IP. Specify it manually with --allow-ip <ip>."
        exit 1
    fi
    success "Detected IP: $deployer_ip"
fi

# ---------------------------------------------------------------------------
# IP-restriction mode: set env values consumed by Bicep and deploy helper
# ---------------------------------------------------------------------------
if [[ "$USE_IP_RESTRICTION" == "true" && "$UPGRADE" != "true" ]]; then
    info "Configuring IP-restriction mode (no Entra ID auth required)"

    # Build the IP allow-list
    ip_list="$deployer_ip"
    if [[ -n "$ALLOWED_IPS" ]]; then
        ip_list="${ip_list},${ALLOWED_IPS}"
    fi

    azd env set USE_IP_RESTRICTION "true" >/dev/null
    azd env set ALLOWED_IP_ADDRESSES "$ip_list" >/dev/null
    info "Allowed IPs: $ip_list"

    # Disable Entra auth flags so deploy helper skips app-reg creation
    azd env set WEB_AUTH_CLIENT_ID "__ip_restrict__" >/dev/null
    EXTRA_DEPLOY_ARGS+=(--web-auth-client-id __ip_restrict__)
elif [[ "$UPGRADE" != "true" ]]; then
    # Ensure the deploy helper creates/reuses an Entra app registration
    EXTRA_DEPLOY_ARGS+=(--create-web-auth-app)
fi

# ---------------------------------------------------------------------------
# Run the deployment
# ---------------------------------------------------------------------------
deploy_cmd=(
    "$SCRIPT_DIR/scripts/deploy_azure_pipeline.sh"
    --resource-group "$RESOURCE_GROUP"
    --environment-name "$ENVIRONMENT_NAME"
    --deployment-slot "$DEPLOYMENT_SLOT"
)

if [[ -n "$LOCATION" ]]; then
    deploy_cmd+=(--location "$LOCATION")
fi
if [[ -n "$SUBSCRIPTION" ]]; then
    deploy_cmd+=(--subscription "$SUBSCRIPTION")
fi
if [[ "$SKIP_PROVISION" == "true" ]]; then
    deploy_cmd+=(--skip-provision)
fi
if [[ "$SKIP_REFRESH" == "true" ]]; then
    deploy_cmd+=(--skip-refresh)
fi
if [[ "$USE_PREBUILT" == "true" ]]; then
    deploy_cmd+=(--use-prebuilt)
fi
if [[ -n "$GHCR_IMAGE" ]]; then
    deploy_cmd+=(--ghcr-image "$GHCR_IMAGE")
fi
if [[ -n "$WEB_PACKAGE_URL" ]]; then
    deploy_cmd+=(--web-package-url "$WEB_PACKAGE_URL")
fi
if [[ -n "$RELEASE_TAG" ]]; then
    deploy_cmd+=(--release-tag "$RELEASE_TAG")
fi
deploy_cmd+=("${EXTRA_DEPLOY_ARGS[@]}")

info "Starting deployment..."
echo ""
"${deploy_cmd[@]}"
deploy_exit=$?

# ---------------------------------------------------------------------------
# Post-deploy: apply IP restrictions if in IP-restriction mode
# ---------------------------------------------------------------------------
if [[ "$USE_IP_RESTRICTION" == "true" && "$UPGRADE" != "true" && "$deploy_exit" -eq 0 ]]; then
    info "Applying Web App IP restrictions..."

    # Resolve web app name from azd env or live resource group
    web_app_name="$(azd env get-value webAppName 2>/dev/null || true)"
    if [[ -z "$web_app_name" ]]; then
        web_app_name="$(az webapp list -g "$RESOURCE_GROUP" --query "[?tags.\"azd-service-name\"=='web'].name | [0]" -o tsv 2>/dev/null || true)"
    fi

    if [[ -z "$web_app_name" ]]; then
        warn "Could not resolve web app name — skipping IP restriction application"
    else
        # Disable built-in Entra auth so the site is reachable without sign-in
        az webapp auth update --resource-group "$RESOURCE_GROUP" --name "$web_app_name" \
            --enabled false 2>/dev/null || true

        # Build access-restriction rules — one per IP/CIDR
        IFS=',' read -r -a ip_array <<< "$deployer_ip${ALLOWED_IPS:+,$ALLOWED_IPS}"

        for access_slot in production qa; do
            access_slot_args=()
            access_label="production"
            if [[ "$access_slot" == "qa" ]]; then
                access_slot_args+=(--slot qa)
                access_label="qa"
            fi

            existing_rules="$(az webapp config access-restriction show \
                -g "$RESOURCE_GROUP" -n "$web_app_name" "${access_slot_args[@]}" \
                --query "ipSecurityRestrictions[?name!='Allow all' && name!='Deny all'].name" -o tsv 2>/dev/null || true)"
            for rule_name in $existing_rules; do
                az webapp config access-restriction remove \
                    -g "$RESOURCE_GROUP" -n "$web_app_name" "${access_slot_args[@]}" \
                    --rule-name "$rule_name" 2>/dev/null || true
            done

            priority=100
            for ip_entry in "${ip_array[@]}"; do
                ip_entry="$(echo "$ip_entry" | xargs)"
                [[ -z "$ip_entry" ]] && continue
                [[ "$ip_entry" == */* ]] || ip_entry="${ip_entry}/32"

                rule_name="AllowIP-${priority}"
                az webapp config access-restriction add \
                    -g "$RESOURCE_GROUP" -n "$web_app_name" "${access_slot_args[@]}" \
                    --rule-name "$rule_name" \
                    --action Allow \
                    --ip-address "$ip_entry" \
                    --priority "$priority" \
                    2>/dev/null
                success "Added $access_label access rule: $rule_name -> $ip_entry"
                ((priority += 10))
            done

            az webapp config access-restriction set \
                -g "$RESOURCE_GROUP" -n "$web_app_name" "${access_slot_args[@]}" \
                --use-same-restrictions-for-scm-site false \
                2>/dev/null || true
        done

        # Probe the actual app hostname from every available host network stack.
        web_hostname="$(az webapp show -g "$RESOURCE_GROUP" -n "$web_app_name" --query defaultHostName -o tsv 2>/dev/null || true)"
        if [[ -n "$web_hostname" ]]; then
            info "Verifying access from this machine..."
            sleep 5

            probe_clients=("shell:curl")
            windows_curl="/mnt/c/Windows/System32/curl.exe"
            if [[ -x "$windows_curl" ]]; then
                probe_clients+=("windows:$windows_curl")
            fi

            for probe_client in "${probe_clients[@]}"; do
                probe_label="${probe_client%%:*}"
                probe_command="${probe_client#*:}"

                if probe_web_access "$probe_label" "$probe_command" "$web_hostname"; then
                    probe_result=0
                else
                    probe_result=$?
                fi
                if (( probe_result != 0 )); then
                    exit 1
                fi

                if (( ${#PROBE_FORBIDDEN_IPS[@]} == 1 )); then
                    forbidden_ip="${PROBE_FORBIDDEN_IPS[0]}"
                    warn "Azure sees $probe_label traffic from $forbidden_ip"
                    info "Adding stable $probe_label egress IP to the allow-list..."
                    az webapp config access-restriction add \
                        -g "$RESOURCE_GROUP" -n "$web_app_name" \
                        --rule-name "AllowIP-${priority}" \
                        --action Allow \
                        --ip-address "${forbidden_ip}/32" \
                        --priority "$priority"
                    success "Added access rule: AllowIP-${priority} -> ${forbidden_ip}/32"
                    ALLOWED_IPS="${ALLOWED_IPS:+${ALLOWED_IPS},}${forbidden_ip}"
                    ((priority += 10))

                    sleep 5
                    if probe_web_access "$probe_label" "$probe_command" "$web_hostname" 3; then
                        probe_result=0
                    else
                        probe_result=$?
                    fi
                    if (( probe_result != 0 || ${#PROBE_FORBIDDEN_IPS[@]} > 0 )); then
                        error "$probe_label traffic is still blocked after adding $forbidden_ip."
                        error "The source IP is changing; configure a fixed VPN egress IP or use Entra ID authentication."
                        exit 1
                    fi
                fi

                success "Web app is accessible through the $probe_label network path"
            done
        fi

        info "Web App IP restrictions applied. Function App remains private via VNet."
    fi
fi

if [[ "$deploy_exit" -eq 0 ]]; then
    echo ""
    success "Deployment complete."

    web_url="$(azd env get-value webAppUrl 2>/dev/null || true)"
    if [[ -n "$web_url" ]]; then
        info "Web app: $web_url"
    fi

    if [[ "$USE_IP_RESTRICTION" == "true" ]]; then
        if [[ "$UPGRADE" == "true" ]]; then
            info "Access mode: IP-restricted (existing live rules preserved)"
        else
            info "Access mode: IP-restricted (allowed: ${deployer_ip}${ALLOWED_IPS:+, ${ALLOWED_IPS}})"
            info "To add more IPs later:"
            info "  az webapp config access-restriction add -g $RESOURCE_GROUP -n <web-app> --rule-name AllowExtra --action Allow --ip-address <cidr> --priority 200"
        fi
    else
        info "Access mode: Entra ID integrated auth"
    fi
    info "Deployment target: $DEPLOYMENT_SLOT"
    if [[ "$DEPLOYMENT_SLOT" == "qa" && -n "$RELEASE_TAG" ]]; then
        azd env set QA_RELEASE_TAG "$RELEASE_TAG" >/dev/null
        azd env set QA_GHCR_IMAGE "$GHCR_IMAGE" >/dev/null
        azd env set QA_WEB_PACKAGE_URL "$WEB_PACKAGE_URL" >/dev/null
        info "Pinned QA release: $RELEASE_TAG"
    elif [[ "$DEPLOYMENT_SLOT" == "prod" ]]; then
        deployed_web_app_name="$(azd env get-value webAppName)"
        promoted_release="$(az webapp config appsettings list \
            -g "$RESOURCE_GROUP" -n "$deployed_web_app_name" \
            --query "[?name=='DEPLOYED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        rollback_release="$(az webapp config appsettings list \
            -g "$RESOURCE_GROUP" -n "$deployed_web_app_name" --slot qa \
            --query "[?name=='DEPLOYED_RELEASE_TAG'].value | [0]" -o tsv 2>/dev/null || true)"
        if [[ -n "$promoted_release" ]]; then
            azd env set PROD_RELEASE_TAG "$promoted_release" >/dev/null
            info "Promoted production release: $promoted_release"
        fi
        if [[ -n "$rollback_release" ]]; then
            azd env set QA_RELEASE_TAG "$rollback_release" >/dev/null
            info "QA rollback release: $rollback_release"
        fi
    fi
else
    error "Deployment failed (exit code $deploy_exit)."
    exit "$deploy_exit"
fi
