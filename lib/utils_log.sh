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
display_summary() {
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

# Some scripts define their own display_summary(); this helper avoids name
# collisions while still exposing the global execution summary.
display_execution_summary() {
    display_summary
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
    
    # Check Azure CLI
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI not found. Please install Azure CLI v2.50 or higher"
        exit 1
    fi
    
    local az_version=$(az version --output json 2>/dev/null | jq -r '."azure-cli"' || echo "unknown")
    log_info "Azure CLI version: $az_version"
    
    # Check jq
    if ! command -v jq &> /dev/null; then
        log_error "jq not found. Please install jq for JSON processing"
        exit 1
    fi
    
    local jq_version=$(jq --version 2>/dev/null || echo "unknown")
    log_info "jq version: $jq_version"
    
    # Check curl
    if ! command -v curl &> /dev/null; then
        log_error "curl not found. Please install curl"
        exit 1
    fi
    
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
