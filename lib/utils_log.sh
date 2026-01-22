#!/usr/bin/env bash
# ==============================================================================
# Logging and Error Handling Utilities
# ==============================================================================

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# If output is not a TTY or NO_COLOR is set, disable color codes to avoid
# raw escape sequences showing up in logs/pipes.
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
fi

# Counters for summary
ERROR_COUNT=0
WARNING_COUNT=0
API_CALL_COUNT=0
CACHE_HIT_COUNT=0

# If callers run with `set -u`, ensure LOG_FILE always has a safe default.
# Scripts can still override LOG_FILE before calling init_logging.
LOG_FILE="${LOG_FILE:-/dev/null}"

# ==============================================================================
# Initialize logging
# ==============================================================================
init_logging() {
    : > "${LOG_FILE}"
    log_info "Log file initialized: ${LOG_FILE}"
}

# ==============================================================================
# Log functions
# ==============================================================================
log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $msg" | tee -a "${LOG_FILE}" >&2
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $msg" | tee -a "${LOG_FILE}" >&2
}

log_warning() {
    local msg="$1"
    ((WARNING_COUNT++))
    echo -e "${YELLOW}[WARNING]${NC} $msg" | tee -a "${LOG_FILE}" >&2
}

log_error() {
    local msg="$1"
    ((ERROR_COUNT++))
    echo -e "${RED}[ERROR]${NC} $msg" | tee -a "${LOG_FILE}" >&2
}

log_debug() {
    local msg="$1"
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "[DEBUG] $msg" >> "${LOG_FILE}"
    fi
}

# ==============================================================================
# Track API calls and cache hits
# ==============================================================================
increment_api_call() {
    ((API_CALL_COUNT++))
}

increment_cache_hit() {
    ((CACHE_HIT_COUNT++))
}

# ==============================================================================
# Display execution summary
# ==============================================================================
utils_log_display_summary() {
    log_info "=== Execution Summary ==="
    log_info "Total Errors: $ERROR_COUNT"
    log_info "Total Warnings: $WARNING_COUNT"
    log_info "API Calls Made: $API_CALL_COUNT"
    log_info "Cache Hits: $CACHE_HIT_COUNT"
    
    if [[ $CACHE_HIT_COUNT -gt 0 && $API_CALL_COUNT -gt 0 ]]; then
        local total=$((API_CALL_COUNT + CACHE_HIT_COUNT))
        local hit_rate=$((CACHE_HIT_COUNT * 100 / total))
        log_info "Cache Hit Rate: ${hit_rate}%"
    fi
    
    log_info "Log file: ${LOG_FILE}"
}

# Backward-compatible name used by inv.sh and others. Scripts may override this
# with their own UI summary; for the logging summary, call display_execution_summary.
display_summary() {
    utils_log_display_summary
}

# Stable name that won't collide with per-script display_summary() functions.
display_execution_summary() {
    utils_log_display_summary
}

# ==============================================================================
# Determine exit code based on execution status
# ==============================================================================
determine_exit_code() {
    if [[ $ERROR_COUNT -gt 0 ]]; then
        log_error "Script failed with $ERROR_COUNT errors"
        exit 1
    else
        log_success "Script completed successfully"
        exit 0
    fi
}

# ==============================================================================
# Verify prerequisites
# ==============================================================================
verify_prerequisites() {
    log_info "Verifying prerequisites..."

    # Helper to fail with actionable install guidance.
    require_cmd() {
        local cmd="$1"
        local install_hint="$2"

        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "Missing dependency: '$cmd'"
            if [[ -n "$install_hint" ]]; then
                log_info "Install hint: $install_hint"
            fi
            exit 1
        fi
    }
    
    # Check Azure CLI
    require_cmd "az" "Azure CLI required. See: https://learn.microsoft.com/cli/azure/install-azure-cli-linux (Debian/Ubuntu quick install: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash)"
    
    local az_version=$(az version --output json 2>/dev/null | jq -r '."azure-cli"' || echo "unknown")
    log_info "Azure CLI version: $az_version"
    
    # Check jq
    require_cmd "jq" "Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y jq (RHEL/CentOS/Fedora: sudo dnf install -y jq)"
    
    local jq_version=$(jq --version 2>/dev/null || echo "unknown")
    log_info "jq version: $jq_version"
    
    # Check curl
    require_cmd "curl" "Debian/Ubuntu: sudo apt-get update && sudo apt-get install -y curl (RHEL/CentOS/Fedora: sudo dnf install -y curl)"

    # Common Unix tools used across scripts/libs
    require_cmd "awk" "Debian/Ubuntu: sudo apt-get install -y gawk (or mawk)"
    require_cmd "sort" "Provided by coreutils (Debian/Ubuntu: sudo apt-get install -y coreutils)"
    require_cmd "sed" "Provided by sed (Debian/Ubuntu: sudo apt-get install -y sed)"
    require_cmd "du" "Provided by coreutils (Debian/Ubuntu: sudo apt-get install -y coreutils)"
    require_cmd "mktemp" "Provided by coreutils (Debian/Ubuntu: sudo apt-get install -y coreutils)"
    require_cmd "sha256sum" "Provided by coreutils (Debian/Ubuntu: sudo apt-get install -y coreutils)"
    require_cmd "stat" "Provided by coreutils (Debian/Ubuntu: sudo apt-get install -y coreutils)"
    require_cmd "column" "Provided by util-linux (Debian/Ubuntu: sudo apt-get install -y util-linux)"
    
    log_success "All prerequisites verified"
}

# ==============================================================================
# Verify Azure login
# ==============================================================================
verify_azure_login() {
    log_info "Verifying Azure login..."
    
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login'"
        exit 1
    fi
    
    local account_name=$(az account show --query "name" -o tsv 2>/dev/null)
    local account_id=$(az account show --query "id" -o tsv 2>/dev/null)
    
    log_info "Logged in as: $account_name ($account_id)"
    log_success "Azure login verified"
}
