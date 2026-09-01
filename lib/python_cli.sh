#!/usr/bin/env bash
# ==============================================================================
# Python CLI integration helpers for curated catalog enrichment and rendering
# ==============================================================================

PYTHON_CLI_PROJECT_ROOT="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FEATURE_CATALOG_SOURCE="${PYTHON_CLI_PROJECT_ROOT}/data/feature_catalog/services.json"
FEATURE_CATALOG_SNAPSHOT="${PYTHON_CLI_PROJECT_ROOT}/data/generated/feature_catalog.snapshot.json"
FEATURE_CATALOG_SQLITE="${PYTHON_CLI_PROJECT_ROOT}/data/generated/feature_catalog.db"
FEATURE_CATALOG_IDENTITY_SNAPSHOT="${PYTHON_CLI_PROJECT_ROOT}/data/generated/canonical_service_identity.snapshot.json"
FEATURE_CATALOG_IDENTITY_GAP_REPORT="${PYTHON_CLI_PROJECT_ROOT}/data/generated/canonical_identity_gaps.snapshot.json"

get_repo_python() {
    local candidates=(
        "${PYTHON_CLI_PROJECT_ROOT}/.venv/bin/python"
        "python3"
        "python"
    )
    local candidate

    for candidate in "${candidates[@]}"; do
        if command -v "$candidate" >/dev/null 2>&1; then
            command -v "$candidate"
            return 0
        fi
    done

    return 1
}

region_has_availability_zones() {
    local region="$1"
    local regions_cache="${REGIONS_CACHE:-}"
    local subscription_id=""

    if [[ -z "$region" ]]; then
        echo "unknown"
        return 0
    fi

    if [[ -z "$regions_cache" ]]; then
        regions_cache="${PYTHON_CLI_PROJECT_ROOT}/.cache/azure_regions.json"
    fi

    mkdir -p "$(dirname "$regions_cache")"

    if declare -F fetch_azure_regions >/dev/null 2>&1; then
        REGIONS_CACHE="$regions_cache" fetch_azure_regions >/dev/null 2>&1 || true
    fi

    if [[ ! -s "$regions_cache" ]] && command -v az >/dev/null 2>&1; then
        subscription_id="$(az account show --query id -o tsv 2>> "${LOG_FILE:-/dev/null}" || true)"
        if [[ -n "$subscription_id" ]]; then
            az rest \
                --method get \
                --url "$(build_arm_url "/subscriptions/${subscription_id}/locations?api-version=2022-12-01")" \
                --query 'value' \
                --output json > "$regions_cache" 2>> "${LOG_FILE:-/dev/null}" || true
        fi
    fi

    if [[ ! -s "$regions_cache" ]] && command -v az >/dev/null 2>&1; then
        az account list-locations --output json > "$regions_cache" 2>> "${LOG_FILE:-/dev/null}" || true
    fi

    if [[ -f "$regions_cache" ]]; then
        local has_zones
        has_zones=$(jq -r --arg region "$region" '
            [ .[] | select(.name == $region) | ((.availabilityZoneMappings // []) | length > 0) ]
            | if length == 0 then "unknown" else (.[0] | tostring) end
        ' "$regions_cache" 2>/dev/null)

        if [[ -n "$has_zones" ]]; then
            echo "$has_zones"
            return 0
        fi
    fi

    echo "unknown"
}

ensure_feature_catalog_artifacts() {
    if [[ ! -f "$FEATURE_CATALOG_SOURCE" ]]; then
        log_warning "Curated feature catalog source not found: $FEATURE_CATALOG_SOURCE"
        return 1
    fi

    local python_bin
    python_bin=$(get_repo_python) || {
        log_warning "Python not available; skipping curated feature catalog build"
        return 1
    }

    mkdir -p "$(dirname "$FEATURE_CATALOG_SNAPSHOT")"

    if [[ -f "$FEATURE_CATALOG_SNAPSHOT" && -f "$FEATURE_CATALOG_SQLITE" && -f "$FEATURE_CATALOG_IDENTITY_SNAPSHOT" && "$FEATURE_CATALOG_SOURCE" -ot "$FEATURE_CATALOG_SNAPSHOT" && "$FEATURE_CATALOG_SOURCE" -ot "$FEATURE_CATALOG_SQLITE" && "$FEATURE_CATALOG_SOURCE" -ot "$FEATURE_CATALOG_IDENTITY_SNAPSHOT" ]]; then
        return 0
    fi

    log_info "Building curated feature catalog artifacts with Python CLI"

    PYTHONPATH="${PYTHON_CLI_PROJECT_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
        "$python_bin" -m azure_compare_cli build-catalog \
        --source "$FEATURE_CATALOG_SOURCE" \
        --output-json "$FEATURE_CATALOG_SNAPSHOT" \
        --output-sqlite "$FEATURE_CATALOG_SQLITE" \
        --output-identity-json "$FEATURE_CATALOG_IDENTITY_SNAPSHOT" >> "${LOG_FILE:-/dev/null}" 2>&1 || {
        log_warning "Failed to build curated feature catalog artifacts"
        return 1
    }

    return 0
}

enrich_provider_comparison_json() {
    local json_file="$1"
    local source_region="$2"
    local target_region="$3"

    [[ -f "$json_file" ]] || return 1

    ensure_feature_catalog_artifacts || return 1

    local python_bin
    python_bin=$(get_repo_python) || return 1

    local source_has_zones target_has_zones
    source_has_zones=$(region_has_availability_zones "$source_region")
    target_has_zones=$(region_has_availability_zones "$target_region")

    PYTHONPATH="${PYTHON_CLI_PROJECT_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
        "$python_bin" -m azure_compare_cli enrich-provider-comparison \
        --input "$json_file" \
        --output "$json_file" \
        --catalog "$FEATURE_CATALOG_SNAPSHOT" \
        --source-region-has-zones "$source_has_zones" \
        --target-region-has-zones "$target_has_zones" >> "${LOG_FILE:-/dev/null}" 2>&1 || {
        log_warning "Curated comparison enrichment failed for $json_file"
        return 1
    }

    return 0
}

render_provider_comparison_report() {
    local json_file="$1"

    [[ -f "$json_file" ]] || return 1

    ensure_feature_catalog_artifacts || return 1

    local python_bin
    python_bin=$(get_repo_python) || return 1

    PYTHONPATH="${PYTHON_CLI_PROJECT_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
        "$python_bin" -m azure_compare_cli render-provider-comparison \
        --input "$json_file"
}

build_identity_gap_report_json() {
    local input_json="$1"
    local output_json="${2:-$FEATURE_CATALOG_IDENTITY_GAP_REPORT}"

    [[ -f "$input_json" ]] || return 1

    local python_bin
    python_bin=$(get_repo_python) || return 1

    mkdir -p "$(dirname "$output_json")"

    PYTHONPATH="${PYTHON_CLI_PROJECT_ROOT}/src${PYTHONPATH:+:$PYTHONPATH}" \
        "$python_bin" -m azure_compare_cli build-identity-gap-report \
        --input "$input_json" \
        --output "$output_json" >> "${LOG_FILE:-/dev/null}" 2>&1 || {
        log_warning "Identity gap report generation failed for $input_json"
        return 1
    }

    return 0
}