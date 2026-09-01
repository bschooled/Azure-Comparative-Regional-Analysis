#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

export NO_COLOR=1
export VALIDATE_SERVICE_CATALOG=false

SOURCE_REGION="eastus"
TARGET_REGION="centralus"
OUTPUT_FILE="${PROJECT_ROOT}/output/${SOURCE_REGION}_vs_${TARGET_REGION}_providers.json"

log() {
    echo "$*"
}

assert_non_empty_metadata() {
    local provider="$1"
    local region="$2"
    local minimum_count="$3"

    local type_count
    type_count=$(bash -lc "cd '$PROJECT_ROOT' && source lib/service_comparison.sh >/dev/null 2>&1; get_provider_region_metadata '$provider' '$region' | jq '(.types // []) | length'" 2>/dev/null)

    if [[ -z "$type_count" ]] || ! [[ "$type_count" =~ ^[0-9]+$ ]] || [[ "$type_count" -lt "$minimum_count" ]]; then
        log "[FAIL] Expected ${provider} metadata in ${region} to expose at least ${minimum_count} deployable resource types; got '${type_count:-empty}'"
        return 1
    fi

    log "[PASS] ${provider} metadata in ${region}: ${type_count} resource types"
}

assert_status_not() {
    local provider="$1"
    local forbidden_status="$2"

    local status
    status=$(jq -r --arg provider "$provider" '.[] | select(.provider == $provider) | .status' "$OUTPUT_FILE")

    if [[ -z "$status" ]]; then
        log "[FAIL] Provider '${provider}' not found in ${OUTPUT_FILE}"
        return 1
    fi

    if [[ "$status" == "$forbidden_status" ]]; then
        log "[FAIL] Provider '${provider}' unexpectedly resolved to status '${forbidden_status}'"
        return 1
    fi

    log "[PASS] ${provider} status is ${status}"
}

assert_status_in() {
    local provider="$1"
    shift

    local status
    status=$(jq -r --arg provider "$provider" '.[] | select(.provider == $provider) | .status' "$OUTPUT_FILE")

    if [[ -z "$status" ]]; then
        log "[FAIL] Provider '${provider}' not found in ${OUTPUT_FILE}"
        return 1
    fi

    local expected
    for expected in "$@"; do
        if [[ "$status" == "$expected" ]]; then
            log "[PASS] ${provider} status is ${status}"
            return 0
        fi
    done

    log "[FAIL] ${provider} status '${status}' was not in expected set: $*"
    return 1
}

main() {
    log "================================================================================"
    log "services_compare Regression Test"
    log "================================================================================"

    cd "$PROJECT_ROOT"

    log "[INFO] Rebuilding ${SOURCE_REGION} vs ${TARGET_REGION} comparison output..."
    ./scripts/root/services_compare.sh --source-region "$SOURCE_REGION" --target-region "$TARGET_REGION" >/dev/null

    if [[ ! -f "$OUTPUT_FILE" ]]; then
        log "[FAIL] Expected output file not found: $OUTPUT_FILE"
        return 1
    fi

    log "[INFO] Validating filtered provider metadata helper..."
    assert_non_empty_metadata "Microsoft.App" "$SOURCE_REGION" 1
    assert_non_empty_metadata "Microsoft.Web" "$SOURCE_REGION" 1
    assert_non_empty_metadata "Microsoft.Sql" "$SOURCE_REGION" 1

    log "[INFO] Validating representative provider statuses..."
    assert_status_not "Microsoft.App" "NOT_AVAILABLE"
    assert_status_not "Microsoft.Web" "NOT_AVAILABLE"
    assert_status_not "Microsoft.Storage" "NOT_AVAILABLE"
    assert_status_not "Microsoft.Sql" "NOT_AVAILABLE"
    assert_status_not "Microsoft.ContainerService" "NOT_AVAILABLE"

    assert_status_in "Microsoft.App" "AVAILABLE_NO_SKUS" "FULL_MATCH" "SOURCE_EXTENDED" "TARGET_EXTENDED"
    assert_status_in "Microsoft.Web" "AVAILABLE_NO_SKUS" "FULL_MATCH" "SOURCE_EXTENDED" "TARGET_EXTENDED"
    assert_status_in "Microsoft.Storage" "FULL_MATCH" "SOURCE_EXTENDED" "TARGET_EXTENDED"
    assert_status_in "Microsoft.Sql" "FULL_MATCH" "SOURCE_EXTENDED" "TARGET_EXTENDED" "SOURCE_RESTRICTED" "TARGET_RESTRICTED"

    log "[INFO] Regression checks passed."
}

main "$@"