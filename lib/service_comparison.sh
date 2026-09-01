#!/bin/bash
################################################################################
# File: lib/service_comparison.sh
# Purpose: Service discovery and comparison between Azure regions
# Features:
#   - Enumerate all Azure services in a region
#   - Fetch SKU information for major service categories
#   - Compare services and SKUs across regions
#   - Generate comparative analysis reports
################################################################################

# Import dependencies
source "$(dirname "${BASH_SOURCE[0]}")/utils_log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/utils_cache.sh"
source "$(dirname "${BASH_SOURCE[0]}")/display.sh"
source "$(dirname "${BASH_SOURCE[0]}")/data_processing.sh"
source "$(dirname "${BASH_SOURCE[0]}")/service_catalog.sh"

################################################################################
# CONFIGURATION
################################################################################

# Default cache TTL (24 hours for service metadata)
SC_CACHE_TTL_SERVICES=${SC_CACHE_TTL_SERVICES:-86400}
SC_CACHE_TTL_SKUS=${SC_CACHE_TTL_SKUS:-86400}

# API rate limiting (conservative to avoid throttling)
SC_API_DELAY_MS=${SC_API_DELAY_MS:-500}
SC_MAX_RETRIES=${SC_MAX_RETRIES:-3}
SC_FEATURE_CATALOG_FILE="${SC_FEATURE_CATALOG_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/data/feature_catalog/services.json}"
SC_SERVICE_CATALOG_FILE="${SC_SERVICE_CATALOG_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/service_catalog.sh}"

# Cache keys must be subscription-aware for any SKU discovery that is scoped to a
# subscription (capabilities endpoints, provider /skus, etc.). Otherwise switching
# subscriptions can incorrectly reuse empty/partial results.
get_current_subscription_id() {
    az account show --query id -o tsv 2>/dev/null || echo ""
}

extract_first_reason_from_capabilities() {
    # Some Azure CLI "capabilities" outputs return an array of objects containing
    # a human-readable reason when the subscription is restricted.
    jq -r '[.[]?.reason?]
        | map(select(type=="string" and length>0) | gsub("\\s+$"; ""))
        | first // empty' 2>/dev/null
}

# Service categories to process
declare -A SC_SERVICE_CATEGORIES=(
    [compute]="Microsoft.Compute"
    [storage]="Microsoft.Storage"
    [database]="Microsoft.Sql,Microsoft.DBforMySQL,Microsoft.DBforPostgreSQL,Microsoft.DocumentDB"
    [fabric]="Microsoft.Fabric"
    [network]="Microsoft.Network"
    [containers]="Microsoft.ContainerRegistry,Microsoft.ContainerService"
    [analytics]="Microsoft.Synapse,Microsoft.Databricks,Microsoft.DataFactory"
)

provider_cache_token() {
    local provider="$1"
    echo "${provider//\//__}"
}

canonicalize_provider_namespace() {
    local provider="$1"
    local provider_lower="${provider,,}"
    local category
    local candidate

    for category in "${!SERVICE_PROVIDERS[@]}"; do
        for candidate in ${SERVICE_PROVIDERS[$category]}; do
            if [[ "${candidate,,}" == "$provider_lower" ]]; then
                echo "$candidate"
                return 0
            fi
        done
    done

    case "$provider_lower" in
        microsoft.analysisservices) echo "Microsoft.AnalysisServices" ;;
        microsoft.apimanagement) echo "Microsoft.ApiManagement" ;;
        microsoft.appconfiguration) echo "Microsoft.AppConfiguration" ;;
        microsoft.appplatform) echo "Microsoft.AppPlatform" ;;
        microsoft.fabric) echo "Microsoft.Fabric" ;;
        microsoft.logic) echo "Microsoft.Logic" ;;
        microsoft.netapp) echo "Microsoft.NetApp" ;;
        *) echo "$provider" ;;
    esac
}

cache_is_fresher_than_sources() {
    local cache_key="$1"
    shift

    local cache_file="${CACHE_DIR:-.cache}/${cache_key}.json"
    [[ -f "$cache_file" ]] || return 1

    local cache_mtime
    cache_mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)

    local source_file
    local source_mtime
    for source_file in "$@"; do
        [[ -f "$source_file" ]] || continue
        source_mtime=$(stat -c %Y "$source_file" 2>/dev/null || stat -f %m "$source_file" 2>/dev/null || echo 0)
        if [[ "$source_mtime" -gt "$cache_mtime" ]]; then
            return 1
        fi
    done

    return 0
}

get_deployable_provider_cache_key() {
    local cloud_name
    cloud_name=$(get_active_azure_cloud_name | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
    echo "deployable_provider_targets_${cloud_name:-azurecloud}"
}

get_deployable_providers() {
    local cache_key
    cache_key=$(get_deployable_provider_cache_key)

    if check_cache "$cache_key" "$SC_CACHE_TTL_SERVICES" \
        && cache_is_fresher_than_sources "$cache_key" "$SC_FEATURE_CATALOG_FILE" "$SC_SERVICE_CATALOG_FILE"; then
        log_info "[CACHE HIT] Deployable provider targets"
        read_cache "$cache_key"
        return 0
    fi

    local providers
    log_info "[BUILD] Rebuilding deployable provider targets"
    providers=$({
        if [[ -f "$SC_FEATURE_CATALOG_FILE" ]]; then
            while IFS= read -r provider; do
                [[ -n "$provider" ]] || continue
                canonicalize_provider_namespace "$provider"
            done < <(jq -r '.services[].providers[]?.namespace // empty' "$SC_FEATURE_CATALOG_FILE" 2>/dev/null || true)
        fi

        if declare -F get_default_deployable_provider_supplements >/dev/null 2>&1; then
            while IFS= read -r provider; do
                [[ -n "$provider" ]] || continue
                canonicalize_provider_namespace "$provider"
            done < <(get_default_deployable_provider_supplements)
        fi
    } | awk 'NF { key=tolower($0); if (!seen[key]++) print $0 }' \
        | LC_ALL=C sort -f)

    write_cache "$cache_key" "$providers" "$SC_CACHE_TTL_SERVICES"
    echo "$providers"
}

get_deployable_resource_types_for_provider() {
    local provider="$1"

    {
        if [[ -n "${SERVICE_RESOURCE_TYPES[$provider]:-}" ]]; then
            tr ',' '\n' <<< "${SERVICE_RESOURCE_TYPES[$provider]}"
        fi

        if [[ -f "$SC_FEATURE_CATALOG_FILE" ]]; then
            jq -r --arg provider "${provider,,}" '
                .services[]
                | .providers[]?
                | select((.namespace // "" | ascii_downcase) == $provider)
                | .resource_types[]?
            ' "$SC_FEATURE_CATALOG_FILE" 2>/dev/null || true
        fi
    } | awk 'NF { key=tolower($0); if (!seen[key]++) print $0 }' \
        | LC_ALL=C sort -f
}

get_provider_definition() {
    local provider="$1"
    local provider_key
    provider_key=$(provider_cache_token "$provider")
    local cache_key="provider_definition_${provider_key}"

    if check_cache "$cache_key" "$SC_CACHE_TTL_SERVICES"; then
        read_cache "$cache_key"
        return 0
    fi

    local provider_definition
    provider_definition=$(az provider show --namespace "$provider" --expand "resourceTypes/locations" --query '{name:namespace, types:resourceTypes[].{name:resourceType, locations:(locations || `[]`)}}' --output json 2>/dev/null) || {
        provider_definition=$(jq -cn --arg provider "$provider" '{name:$provider, types:[]}')
    }

    write_cache "$cache_key" "$provider_definition" "$SC_CACHE_TTL_SERVICES"
    echo "$provider_definition"
}

get_provider_region_metadata() {
    local provider="$1"
    local region="$2"

    if [[ "$provider" == "Microsoft.Compute/disks" ]]; then
        jq -cn --arg provider "$provider" --arg region "$region" '{name:$provider, types:[{name:"disks", locations:[$region]}]}'
        return 0
    fi

    local provider_definition
    provider_definition=$(get_provider_definition "$provider") || return 1

    local allowed_types_json='[]'
    local allowed_types
    allowed_types=$(get_deployable_resource_types_for_provider "$provider" || true)
    if [[ -n "$allowed_types" ]]; then
        allowed_types_json=$(printf '%s\n' "$allowed_types" | jq -Rsc 'split("\n") | map(select(length > 0) | ascii_downcase)')
    fi

    jq -c --arg region "$region" --argjson allowed "$allowed_types_json" '
        def canon: ascii_downcase | gsub("[^a-z0-9]"; "");
        {
            name: (.name // ""),
            types: [
                (.types // [])[]
                | select((((.locations // []) | map(canon)) | index(($region | canon))) != null)
                | . as $resourceType
                | select(($allowed | length) == 0 or (($allowed | index(($resourceType.name // "" | ascii_downcase))) != null))
            ]
        }
    ' <<< "$provider_definition"
}

################################################################################
# SERVICE DISCOVERY
################################################################################

# Function: Get all resource providers available in a region
# Args: region
# Returns: JSON array of providers with their resource types
get_providers_in_region() {
    local region="$1"
    local cache_key="providers_${region}"
    
    # Check cache first
    if check_cache "$cache_key" "$SC_CACHE_TTL_SERVICES"; then
        log_info "[CACHE HIT] Providers for region $region"
        read_cache "$cache_key"
        return 0
    fi
    
    log_info "[FETCH] Fetching resource providers for region: $region"
    log_info "[EXEC] Running: az provider list --expand resourceTypes/locations..."
    
    local providers
    providers=$(az provider list --expand "resourceTypes/locations" --query \
        "[].{name:namespace, types:resourceTypes[?locations.contains(@, '$region')].{name:resourceType, locations:locations}}" \
        --output json 2>/dev/null) || {
        log_error "Failed to fetch providers for region: $region"
        return 1
    }
    
    local count=$(echo "$providers" | jq '. | length' 2>/dev/null || echo "0")
    log_info "[SUCCESS] Found $count providers in region $region"
    
    # Cache the result
    write_cache "$cache_key" "$providers" "$SC_CACHE_TTL_SERVICES"
    
    echo "$providers"
}

# Function: Get services grouped by family
# Args: region
# Returns: JSON object with services grouped by family
get_service_families() {
    local region="$1"
    local cache_key="service_families_${region}"
    
    if check_cache "$cache_key" "$SC_CACHE_TTL_SERVICES"; then
        read_cache "$cache_key"
        return 0
    fi
    
    log_info "Building service families for region: $region"
    
    local providers families
    providers=$(get_providers_in_region "$region")
    
    # Build categorized service families
    families=$(jq -n \
        --argjson providers "$providers" \
        '{
            "compute": ($providers[] | select(.name | startswith("Microsoft.Compute")) | .types),
            "storage": ($providers[] | select(.name | startswith("Microsoft.Storage")) | .types),
            "database": ($providers[] | select(.name | test("Microsoft.(Sql|DBfor|DocumentDB)")) | .types),
            "fabric": ($providers[] | select(.name == "Microsoft.Fabric") | .types),
            "network": ($providers[] | select(.name == "Microsoft.Network") | .types),
            "containers": ($providers[] | select(.name | test("Microsoft.(ContainerRegistry|ContainerService)")) | .types),
            "analytics": ($providers[] | select(.name | test("Microsoft.(Synapse|Databricks|DataFactory)")) | .types),
            "all": $providers
        }')
    
    write_cache "$cache_key" "$families" "$SC_CACHE_TTL_SERVICES"
    
    echo "$families"
}

################################################################################
# SKU DISCOVERY
################################################################################

# Function: Get Compute SKUs for a region
# Args: region
# Returns: JSON array of compute SKUs
get_compute_skus() {
    local region="$1"
    local cache_key="compute_skus_${region}"
    
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi
    
    log_info "Fetching Compute SKUs for region: $region"
    
    local skus
    skus=$(az vm list-skus --location "$region" \
        --query "[].{name:name, resourceType:resourceType, locations:locations, capabilities:capabilities}" \
        --output json 2>/dev/null) || {
        log_warn "Failed to fetch VM SKUs for region: $region, falling back to Azure REST API"
        # Fallback to REST API
        get_compute_skus_rest "$region"
        return $?
    }
    
    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

# Function: Get Compute SKUs via REST API (fallback)
# Args: region
# Returns: JSON array of SKUs
get_compute_skus_rest() {
    local region="$1"
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    
    local url
    url=$(build_arm_url "/subscriptions/${subscription_id}/providers/Microsoft.Compute/skus")
    url+="?api-version=2023-09-01&\$filter=location eq '$region'"
    
    local response
    response=$(az rest --method get --url "$url" --output json 2>/dev/null) || {
        log_error "REST API call failed for compute SKUs"
        return 1
    }
    
    # Extract value array from response
    echo "$response" | jq -r '.value // empty'
}

# Function: Get Storage SKUs for a region
# Args: region
# Returns: JSON array of storage SKUs
get_storage_skus() {
    local region="$1"
    local cache_key="storage_skus_${region}"
    
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi
    
    log_info "Fetching Storage SKUs for region: $region"
    
    local skus
    skus=$(az storage sku list --query \
        "[?locations.contains(@, '$region')].{name:name, locations:locations, tier:tier, kind:kind}" \
        --output json 2>/dev/null) || {
        log_warn "Failed to fetch Storage SKUs for region: $region"
        echo "[]"
        return 0
    }
    
    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

# Function: Get Database SKUs for a region
# Args: region
# Returns: JSON array of database SKUs
get_database_skus() {
    local region="$1"
    local cache_key="database_skus_${region}"
    
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi
    
    log_info "Fetching Database SKUs for region: $region"
    
    local skus=()
    
    # SQL Server SKUs
    local sql_skus
    sql_skus=$(az sql db list-editions --location "$region" \
        --query "[].{name:name, family:editionName, tier:serviceLevelObjectiveName}" \
        --output json 2>/dev/null) || log_warn "Failed to fetch SQL SKUs"
    skus+=("$sql_skus")
    
    # Combine and cache
    local combined
    combined=$(jq -s 'add // []' <<< "${skus[@]}")
    
    write_cache "$cache_key" "$combined" "$SC_CACHE_TTL_SKUS"
    echo "$combined"
}

# Function: Get Fabric SKUs for a region
# Args: region
# Returns: JSON array of fabric SKUs
get_fabric_skus() {
    local region="$1"
    local cache_key="fabric_skus_${region}"
    
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi
    
    log_info "Fetching Fabric SKUs for region: $region"
    
    local subscription_id
    subscription_id=$(az account show --query id -o tsv)
    
    local response skus
    local endpoint
    endpoint=$(build_arm_url "/subscriptions/${subscription_id}/providers/Microsoft.Fabric/skus")
    response=$(az rest --method get \
        --url "${endpoint}?api-version=2023-11-01" \
        --output json 2>/dev/null) || {
        log_warn "Failed to fetch Fabric SKUs for region: $region"
        echo "[]"
        return 0
    }

    # Normalize to array and filter by region.
    # Some providers return human-friendly location names (e.g. "West US 2"), so
    # compare using a canonical form (lowercase, strip non-alphanumerics).
    skus=$(echo "$response" | jq -c --arg region "$region" '
        def canon: ascii_downcase | gsub("[^a-z0-9]"; "");
        def locs: (.locations // (.locationInfo // [] | map(.location)) // []);
        (.value // .)
        | [ .[]? | select((locs | map(canon) | index(($region|canon))) != null) ]
    ' 2>/dev/null)

    if [[ -z "$skus" ]] || ! echo "$skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
        skus="[]"
    fi
    
    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

# Function: Get MySQL Flexible Server SKUs for a region
# Args: region
# Returns: JSON array of SKU-like objects: {name, resourceType}
get_mysql_flexible_server_skus() {
    local region="$1"
    local cache_key="mysql_flexible_skus_${region}"
    local meta_key="mysql_flexible_skus_meta_${region}"

    # Cache-first without requiring Azure CLI login
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi

    # Back-compat / migration: if a subscription-scoped cache exists, use it
    # and also write it into the universal cache key.
    local subscription_id
    subscription_id=$(get_current_subscription_id) || true
    if [[ -n "$subscription_id" ]] && check_cache "mysql_flexible_skus_${region}_${subscription_id}" "$SC_CACHE_TTL_SKUS"; then
        local tmp
        tmp=$(read_cache "mysql_flexible_skus_${region}_${subscription_id}")
        write_cache "$cache_key" "$tmp" "$SC_CACHE_TTL_SKUS"
        read_cache "$cache_key"
        return 0
    fi

    local raw skus reason
    raw=$(az mysql flexible-server list-skus --location "$region" --output json 2>/dev/null) || {
        log_warn "Failed to fetch MySQL Flexible Server SKUs for region: $region"
        write_cache "$meta_key" '{"reason":"Failed to fetch SKUs (az mysql flexible-server list-skus)","restricted":true}' "$SC_CACHE_TTL_SKUS"
        echo "[]" | tee "${CACHE_DIR}/${cache_key}.json" >/dev/null
        return 0
    }

    reason=$(printf '%s' "$raw" | extract_first_reason_from_capabilities || true)
    if [[ -n "$reason" ]]; then
        log_warn "MySQL Flexible Server SKU query returned reason for region $region: $reason"
        write_cache "$meta_key" "$(jq -cn --arg reason "$reason" '{reason:$reason, restricted:true}')" "$SC_CACHE_TTL_SKUS"
    else
        write_cache "$meta_key" '{"reason":null,"restricted":false}' "$SC_CACHE_TTL_SKUS"
    fi

    skus=$(echo "$raw" | jq -c '
        [
          .[]?
          | .supportedFlexibleServerEditions[]?.supportedServerVersions[]?.supportedSkus[]?.name?
          // empty
        ]
        | unique
        | map({name: ., resourceType: "flexibleServers"})
    ' 2>/dev/null)

    if [[ -z "$skus" ]] || ! echo "$skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
        skus="[]"
    fi

    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

# Function: Get PostgreSQL Flexible Server SKUs for a region
# Args: region
# Returns: JSON array of SKU-like objects: {name, resourceType}
get_postgres_flexible_server_skus() {
    local region="$1"
    local cache_key="postgres_flexible_skus_${region}"
    local meta_key="postgres_flexible_skus_meta_${region}"

    # Cache-first without requiring Azure CLI login
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi

    # Back-compat / migration: if a subscription-scoped cache exists, use it
    # and also write it into the universal cache key.
    local subscription_id
    subscription_id=$(get_current_subscription_id) || true
    if [[ -n "$subscription_id" ]] && check_cache "postgres_flexible_skus_${region}_${subscription_id}" "$SC_CACHE_TTL_SKUS"; then
        local tmp
        tmp=$(read_cache "postgres_flexible_skus_${region}_${subscription_id}")
        write_cache "$cache_key" "$tmp" "$SC_CACHE_TTL_SKUS"
        read_cache "$cache_key"
        return 0
    fi

    local raw skus reason
    raw=$(az postgres flexible-server list-skus --location "$region" --output json 2>/dev/null) || {
        log_warn "Failed to fetch PostgreSQL Flexible Server SKUs for region: $region"
        write_cache "$meta_key" '{"reason":"Failed to fetch SKUs (az postgres flexible-server list-skus)","restricted":true}' "$SC_CACHE_TTL_SKUS"
        echo "[]" | tee "${CACHE_DIR}/${cache_key}.json" >/dev/null
        return 0
    }

    reason=$(printf '%s' "$raw" | extract_first_reason_from_capabilities || true)
    if [[ -n "$reason" ]]; then
        log_warn "PostgreSQL Flexible Server SKU query returned reason for region $region: $reason"
        write_cache "$meta_key" "$(jq -cn --arg reason "$reason" '{reason:$reason, restricted:true}')" "$SC_CACHE_TTL_SKUS"
    else
        write_cache "$meta_key" '{"reason":null,"restricted":false}' "$SC_CACHE_TTL_SKUS"
    fi

    # PostgreSQL output shape differs from MySQL; extract from supportedServerEditions[].supportedServerSkus[].name
    # and also from any flexible-server edition shape if present.
    skus=$(echo "$raw" | jq -c '
        [
          .[]?
          | (
              (.supportedServerEditions[]?.supportedServerSkus[]?.name? // empty),
              (.supportedFlexibleServerEditions[]?.supportedServerVersions[]?.supportedSkus[]?.name? // empty)
            )
        ]
        | unique
        | map({name: ., resourceType: "flexibleServers"})
    ' 2>/dev/null)

    if [[ -z "$skus" ]] || ! echo "$skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
        skus="[]"
    fi

    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

# Function: Get Azure SQL Database SKU-like tiers for a region
# Args: region
# Returns: JSON array of SKU-like objects: {name, resourceType}
get_sql_database_skus() {
    local region="$1"
    local cache_key="sql_database_skus_${region}"

    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi

    local raw skus
    raw=$(az sql db list-editions --location "$region" --output json 2>/dev/null) || {
        log_warn "Failed to fetch SQL Database editions for region: $region"
        echo "[]" | tee "${CACHE_DIR}/${cache_key}.json" >/dev/null
        return 0
    }

    # az sql db list-editions returns editions with nested supportedServiceLevelObjectives.
    # Emit stable SKU-like rows as "<Edition>:<SLO>".
    skus=$(echo "$raw" | jq -c '
        [
          .[]? as $ed
          | ($ed.supportedServiceLevelObjectives[]?.name? // empty) as $slo
          | {
              name: ($ed.name + ":" + $slo),
              resourceType: "servers/databases"
            }
        ]
        | unique_by(.name, .resourceType)
    ' 2>/dev/null)

    if [[ -z "$skus" ]] || ! echo "$skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
        skus="[]"
    fi

    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

# Function: Get Managed Disk SKU names for a region (SKU-name-only)
# Args: region
# Returns: JSON array of objects: {name, resourceType:"disks"}
get_managed_disk_skus() {
    local region="$1"
    local cache_key="managed_disk_skus_${region}"

    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        read_cache "$cache_key"
        return 0
    fi

    local raw skus
    raw=$(az vm list-skus --location "$region" --resource-type disks --output json 2>/dev/null) || {
        log_warn "Failed to fetch managed disk SKUs for region: $region"
        echo "[]" | tee "${CACHE_DIR}/${cache_key}.json" >/dev/null
        return 0
    }

    # az vm list-skus returns multiple entries per name (varying capabilities);
    # for planning, we only need distinct SKU names.
    skus=$(echo "$raw" | jq -c '
        [
          .[]?
          | .name?
          | select(type=="string" and length>0)
        ]
        | unique
        | map({name: ., resourceType: "disks"})
    ' 2>/dev/null)

    if [[ -z "$skus" ]] || ! echo "$skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
        skus="[]"
    fi

    write_cache "$cache_key" "$skus" "$SC_CACHE_TTL_SKUS"
    echo "$skus"
}

################################################################################
# COMPARATIVE ANALYSIS
################################################################################

# Function: Compare services between two regions
# Args: source_region target_region
# Returns: JSON object with comparison results
compare_services() {
    local source_region="$1"
    local target_region="$2"
    
    log_info "Comparing services between $source_region and $target_region"
    
    local source_services target_services
    source_services=$(get_service_families "$source_region")
    target_services=$(get_service_families "$target_region")
    
    # Build comparison JSON
    local comparison
    comparison=$(jq -n \
        --arg src "$source_region" \
        --arg tgt "$target_region" \
        --argjson src_svcs "$source_services" \
        --argjson tgt_svcs "$target_services" \
        '{
            sourceRegion: $src,
            targetRegion: $tgt,
            serviceCount: {
                source: ($src_svcs.all | length),
                target: ($tgt_svcs.all | length)
            },
            services: {}
        }')
    
    echo "$comparison"
}

# Function: Compare SKUs between two regions
# Args: source_region target_region category
# Returns: JSON object with SKU comparison
compare_skus() {
    local source_region="$1"
    local target_region="$2"
    local category="${3:-compute}"
    
    log_info "Comparing $category SKUs between $source_region and $target_region"
    
    local source_skus target_skus
    
    case "$category" in
        compute)
            source_skus=$(get_compute_skus "$source_region")
            target_skus=$(get_compute_skus "$target_region")
            ;;
        storage)
            source_skus=$(get_storage_skus "$source_region")
            target_skus=$(get_storage_skus "$target_region")
            ;;
        database)
            source_skus=$(get_database_skus "$source_region")
            target_skus=$(get_database_skus "$target_region")
            ;;
        fabric)
            source_skus=$(get_fabric_skus "$source_region")
            target_skus=$(get_fabric_skus "$target_region")
            ;;
        *)
            log_error "Unknown category: $category"
            return 1
            ;;
    esac

    # Ensure we have valid JSON arrays; if parsing fails, treat as empty
    if ! echo "$source_skus" | jq -e '.' >/dev/null 2>&1; then
        log_warning "Invalid $category SKU payload for $source_region; treating as empty"
        source_skus="[]"
    fi
    if ! echo "$target_skus" | jq -e '.' >/dev/null 2>&1; then
        log_warning "Invalid $category SKU payload for $target_region; treating as empty"
        target_skus="[]"
    fi
    
    # Build comparison
    local comparison
    comparison=$(jq -n \
        --arg cat "$category" \
        --argjson src_skus "$source_skus" \
        --argjson tgt_skus "$target_skus" \
        '{
            category: $cat,
            sourceCount: ($src_skus | length),
            targetCount: ($tgt_skus | length),
            onlyInSource: ($src_skus - $tgt_skus),
            onlyInTarget: ($tgt_skus - $src_skus),
            common: ($src_skus & $tgt_skus | length)
        }')
    
    echo "$comparison"
}

################################################################################
# PROVIDER SKU QUERYING
################################################################################

# Function: Query SKUs for a specific provider and region
# Args: region provider_namespace
# Returns: JSON array of SKUs
query_provider_skus() {
    local region="$1"
    local provider="$2"
    # Universal cache keys (no subscription suffix). Also sanitize provider
    # names so synthetic entries like "Microsoft.Compute/disks" don't create
    # nested paths under CACHE_DIR.
    local provider_key="${provider//\//__}"
    local cache_key="provider_skus_${provider_key}_${region}"

    # Cache-first must work even when offline/not logged into Azure.
    if check_cache "$cache_key" "$SC_CACHE_TTL_SKUS"; then
        if [[ "${CACHE_TRACE:-0}" == "1" ]]; then
            log_info "[CACHE HIT] SKUs for $provider in $region"
        fi
        read_cache "$cache_key"
        return 0
    fi

    # Back-compat / migration: if a subscription-scoped cache exists, use the
    # newest one and write it into the universal cache key.
    local subscription_id
    subscription_id=$(get_current_subscription_id) || true
    local pattern="${CACHE_DIR}/provider_skus_${provider}_${region}_*.json"
    local newest
    newest=$(ls -t $pattern 2>/dev/null | head -n 1 || true)
    if [[ -n "$newest" ]] && is_cache_valid "$newest" "$SC_CACHE_TTL_SKUS"; then
        if [[ "${CACHE_TRACE:-0}" == "1" ]]; then
            log_info "[CACHE HIT] SKUs for $provider in $region (migrated from ${newest##*/})"
        fi
        local tmp
        tmp=$(cat "$newest")
        write_cache "$cache_key" "$tmp" "$SC_CACHE_TTL_SKUS"
        read_cache "$cache_key"
        return 0
    fi

    if [[ "${CACHE_TRACE:-0}" == "1" ]]; then
        log_info "[CACHE MISS] SKUs for $provider in $region"
    fi
    
    # Provider-specific SKU backends (preferred when /skus is missing/empty)
    local filtered_skus
    case "$provider" in
        Microsoft.Compute/disks)
            filtered_skus=$(get_managed_disk_skus "$region" 2>/dev/null || echo "[]")
            ;;
        Microsoft.Fabric)
            filtered_skus=$(get_fabric_skus "$region" 2>/dev/null || echo "[]")
            ;;
        Microsoft.DBforMySQL)
            filtered_skus=$(get_mysql_flexible_server_skus "$region" 2>/dev/null || echo "[]")
            ;;
        Microsoft.DBforPostgreSQL)
            filtered_skus=$(get_postgres_flexible_server_skus "$region" 2>/dev/null || echo "[]")
            ;;
        Microsoft.Sql)
            filtered_skus=$(get_sql_database_skus "$region" 2>/dev/null || echo "[]")
            ;;
        *)
            filtered_skus=""
            ;;
    esac

    # If provider-specific method produced a non-empty array, use it.
    if [[ -n "$filtered_skus" ]] && echo "$filtered_skus" | jq -e 'type=="array" and length > 0' >/dev/null 2>&1; then
        write_cache "$cache_key" "$filtered_skus" "$SC_CACHE_TTL_SKUS"
        echo "$filtered_skus"
        return 0
    fi

    if [[ -z "$subscription_id" ]]; then
        log_warn "No Azure subscription context available; returning empty SKUs for $provider in $region (cache miss)"
        echo "[]"
        return 0
    fi

    # Generic /skus endpoint fallback with multiple api-versions
    local endpoint
    endpoint=$(build_arm_url "/subscriptions/${subscription_id}/providers/${provider}/skus")
    local candidate_versions=()

    # Prefer catalog version if present (may help for some providers)
    if declare -p SERVICE_API_VERSIONS >/dev/null 2>&1; then
        if [[ -n "${SERVICE_API_VERSIONS[$provider]:-}" ]]; then
            candidate_versions+=("${SERVICE_API_VERSIONS[$provider]}")
        fi
    fi

    # Known sku api-versions and fallbacks
    candidate_versions+=("2025-08-01" "2024-11-01" "2024-01-01" "2023-11-01" "2023-09-01" "2021-06-01" "2020-10-01")

    local response api_version
    filtered_skus="[]"
    for api_version in "${candidate_versions[@]}"; do
        response=$(az rest --method get --url "${endpoint}?api-version=${api_version}" --output json 2>/dev/null) || continue

                # Normalize to array and filter by region; handle both .locations and .locationInfo[].location.
                # Canonicalize locations because some providers return display names ("Sweden Central").
                filtered_skus=$(echo "$response" | jq -c --arg region "$region" '
                        def canon: ascii_downcase | gsub("[^a-z0-9]"; "");
                        def locs: (.locations // (.locationInfo // [] | map(.location)) // []);
                        (.value // .)
                        | if type=="array" then
                                [ .[]? | select((locs | map(canon) | index(($region|canon))) != null) ]
                            else
                                []
                            end
                ' 2>/dev/null)

        if [[ -n "$filtered_skus" ]] && echo "$filtered_skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
            break
        fi
        filtered_skus="[]"
    done

    if [[ -z "$filtered_skus" ]] || ! echo "$filtered_skus" | jq -e 'type=="array"' >/dev/null 2>&1; then
        filtered_skus="[]"
    fi
    
    # Cache the result
    write_cache "$cache_key" "$filtered_skus" "$SC_CACHE_TTL_SKUS"
    
    echo "$filtered_skus"
}

################################################################################
# OUTPUT GENERATION
################################################################################

# Function: Generate both CSV and JSON from all available providers
# Args: source_region target_region csv_file json_file
generate_comparison_outputs() {
    local source_region="$1"
    local target_region="$2"
    local csv_file="$3"
    local json_file="$4"
    local provider_scope="${5:-deployable}"
    
    local source_providers target_providers
    local all_providers

    if [[ "$provider_scope" == "all" ]]; then
        log_info "Generating comparison outputs by enumerating all providers..."

        log_info "[STEP 1/5] Fetching providers for $source_region"
        source_providers=$(get_providers_in_region "$source_region") || source_providers="[]"

        log_info "[STEP 2/5] Fetching providers for $target_region"
        target_providers=$(get_providers_in_region "$target_region") || target_providers="[]"

        log_info "[STEP 3/5] Extracting unique provider names"
        all_providers=$(echo -e "$source_providers\n$target_providers" | jq -r '.[].name' | sort -u)
    else
        log_info "Generating comparison outputs from deployable provider catalog..."
        log_info "[STEP 1/5] Building deployable provider list"
        all_providers=$(get_deployable_providers)
        source_providers='[]'
        target_providers='[]'
        log_info "[STEP 2/5] Using per-provider cached definitions for regional availability"
        log_info "[STEP 3/5] Limiting comparison to deployable service namespaces"
    fi

    # Add synthetic resource-type entries that users commonly need SKU breakouts for.
    # (These are not provider namespaces, so they won't appear in the provider list.)
    all_providers=$(printf '%s\n%s\n' "$all_providers" "Microsoft.Compute/disks" | sort -u)
    local provider_count=$(echo "$all_providers" | wc -l)
    log_info "[INFO] Found $provider_count unique providers to process"

    # Pre-compute availability zone status for both regions so that zone-
    # dependent SKUs (ZRS, GZRS, etc.) can be annotated accurately.
    local src_has_zones tgt_has_zones
    if declare -F region_has_availability_zones >/dev/null 2>&1; then
        src_has_zones=$(region_has_availability_zones "$source_region")
        tgt_has_zones=$(region_has_availability_zones "$target_region")
    else
        src_has_zones="unknown"
        tgt_has_zones="unknown"
    fi
    export __SC_SRC_HAS_ZONES="$src_has_zones"
    export __SC_TGT_HAS_ZONES="$tgt_has_zones"
    log_info "[INFO] AZ status: $source_region=$src_has_zones, $target_region=$tgt_has_zones"
    
    # Create temp directory for parallel results
    local temp_dir=$(mktemp -d)
    
    local max_parallel="${PARALLEL:-4}"
    log_info "[STEP 4/5] Processing providers in parallel (${max_parallel} concurrent)..."
    
    # Convert to array for proper iteration
    local provider_array
    mapfile -t provider_array <<< "$all_providers"
    
    # Process providers in parallel
    local provider_idx=0
    for provider in "${provider_array[@]}"; do
        if [[ -z "$provider" ]]; then
            continue
        fi
        ((provider_idx++))
        
        # Wait if we have max_parallel jobs running
        while [[ $(jobs -r | wc -l) -ge "$max_parallel" ]]; do
            sleep 0.1
        done
        
        # Process provider in background
        (
            log_info "[PROVIDER $provider_idx/$provider_count] Processing $provider"
            
            # Check if provider exists in each region (not just SKU count)
            local src_exists tgt_exists
            if [[ "$provider_scope" == "all" ]]; then
                if [[ "$provider" == "Microsoft.Compute/disks" ]]; then
                    # Treat disks as available when Microsoft.Compute exists.
                    src_exists=$(echo "$source_providers" | jq 'any(.[]; .name == "Microsoft.Compute")')
                    tgt_exists=$(echo "$target_providers" | jq 'any(.[]; .name == "Microsoft.Compute")')
                else
                    src_exists=$(echo "$source_providers" | jq "any(.[]; .name == \"$provider\")")
                    tgt_exists=$(echo "$target_providers" | jq "any(.[]; .name == \"$provider\")")
                fi
            else
                local src_provider_metadata tgt_provider_metadata
                src_provider_metadata=$(get_provider_region_metadata "$provider" "$source_region" 2>/dev/null || jq -cn --arg provider "$provider" '{name:$provider, types:[]}')
                tgt_provider_metadata=$(get_provider_region_metadata "$provider" "$target_region" 2>/dev/null || jq -cn --arg provider "$provider" '{name:$provider, types:[]}')
                src_exists=$(jq '((.types // []) | length) > 0' <<< "$src_provider_metadata")
                tgt_exists=$(jq '((.types // []) | length) > 0' <<< "$tgt_provider_metadata")
            fi
            
            # Get resource type counts from provider listings
            local src_types tgt_types
            if [[ "$provider_scope" == "all" ]]; then
                if [[ "$provider" == "Microsoft.Compute/disks" ]]; then
                    src_types=1
                    tgt_types=1
                else
                    src_types=$(echo "$source_providers" | jq "[.[] | select(.name == \"$provider\") | .types | length] | add // 0")
                    tgt_types=$(echo "$target_providers" | jq "[.[] | select(.name == \"$provider\") | .types | length] | add // 0")
                fi
            else
                src_types=$(jq '(.types // []) | length' <<< "$src_provider_metadata")
                tgt_types=$(jq '(.types // []) | length' <<< "$tgt_provider_metadata")
            fi
            
            # Query SKUs for this provider in both regions
            log_info "[SKU QUERY] Querying $provider in both regions"
            local src_skus tgt_skus src_count tgt_count
            if [[ "${CACHE_TRACE:-0}" == "1" ]]; then
                src_skus=$(query_provider_skus "$source_region" "$provider" || echo "[]")
            else
                src_skus=$(query_provider_skus "$source_region" "$provider" 2>/dev/null || echo "[]")
            fi
            src_count=$(echo "$src_skus" | jq '. | length' 2>/dev/null || echo "0")
            
            if [[ "${CACHE_TRACE:-0}" == "1" ]]; then
                tgt_skus=$(query_provider_skus "$target_region" "$provider" || echo "[]")
            else
                tgt_skus=$(query_provider_skus "$target_region" "$provider" 2>/dev/null || echo "[]")
            fi
            tgt_count=$(echo "$tgt_skus" | jq '. | length' 2>/dev/null || echo "0")
            
            log_info "[SKU RESULT] $provider: $src_count in $source_region, $tgt_count in $target_region"

            # Some providers return an empty SKU list due to subscription restrictions.
            # Surface those as explicit status/notes rather than silently reporting "0 SKUs".
            local subscription_id src_note tgt_note src_restricted tgt_restricted
            subscription_id=$(get_current_subscription_id) || true
            src_note=""
            tgt_note=""
            src_restricted=false
            tgt_restricted=false
            # Universal meta cache files (preferred)
            case "$provider" in
                Microsoft.DBforPostgreSQL)
                    if [[ -f "${CACHE_DIR}/postgres_flexible_skus_meta_${source_region}.json" ]]; then
                        src_note=$(jq -r '.reason // empty' "${CACHE_DIR}/postgres_flexible_skus_meta_${source_region}.json" 2>/dev/null || echo "")
                    fi
                    if [[ -f "${CACHE_DIR}/postgres_flexible_skus_meta_${target_region}.json" ]]; then
                        tgt_note=$(jq -r '.reason // empty' "${CACHE_DIR}/postgres_flexible_skus_meta_${target_region}.json" 2>/dev/null || echo "")
                    fi
                    ;;
                Microsoft.DBforMySQL)
                    if [[ -f "${CACHE_DIR}/mysql_flexible_skus_meta_${source_region}.json" ]]; then
                        src_note=$(jq -r '.reason // empty' "${CACHE_DIR}/mysql_flexible_skus_meta_${source_region}.json" 2>/dev/null || echo "")
                    fi
                    if [[ -f "${CACHE_DIR}/mysql_flexible_skus_meta_${target_region}.json" ]]; then
                        tgt_note=$(jq -r '.reason // empty' "${CACHE_DIR}/mysql_flexible_skus_meta_${target_region}.json" 2>/dev/null || echo "")
                    fi
                    ;;
            esac

            # Back-compat: if notes are missing and old subscription-suffixed meta exists, use it.
            if [[ -n "$subscription_id" ]]; then
                if [[ -z "$src_note" && "$provider" == "Microsoft.DBforPostgreSQL" && -f "${CACHE_DIR}/postgres_flexible_skus_meta_${source_region}_${subscription_id}.json" ]]; then
                    src_note=$(jq -r '.reason // empty' "${CACHE_DIR}/postgres_flexible_skus_meta_${source_region}_${subscription_id}.json" 2>/dev/null || echo "")
                fi
                if [[ -z "$tgt_note" && "$provider" == "Microsoft.DBforPostgreSQL" && -f "${CACHE_DIR}/postgres_flexible_skus_meta_${target_region}_${subscription_id}.json" ]]; then
                    tgt_note=$(jq -r '.reason // empty' "${CACHE_DIR}/postgres_flexible_skus_meta_${target_region}_${subscription_id}.json" 2>/dev/null || echo "")
                fi
                if [[ -z "$src_note" && "$provider" == "Microsoft.DBforMySQL" && -f "${CACHE_DIR}/mysql_flexible_skus_meta_${source_region}_${subscription_id}.json" ]]; then
                    src_note=$(jq -r '.reason // empty' "${CACHE_DIR}/mysql_flexible_skus_meta_${source_region}_${subscription_id}.json" 2>/dev/null || echo "")
                fi
                if [[ -z "$tgt_note" && "$provider" == "Microsoft.DBforMySQL" && -f "${CACHE_DIR}/mysql_flexible_skus_meta_${target_region}_${subscription_id}.json" ]]; then
                    tgt_note=$(jq -r '.reason // empty' "${CACHE_DIR}/mysql_flexible_skus_meta_${target_region}_${subscription_id}.json" 2>/dev/null || echo "")
                fi
            fi

            if [[ "$src_exists" == "true" && "$src_count" -eq 0 && -n "$src_note" ]]; then
                src_restricted=true
            fi
            if [[ "$tgt_exists" == "true" && "$tgt_count" -eq 0 && -n "$tgt_note" ]]; then
                tgt_restricted=true
            fi
            
            # Determine status based on provider existence first, then SKU comparison
            local status
            if [[ "$src_exists" == "false" && "$tgt_exists" == "false" ]]; then
                status="NOT_AVAILABLE"
            elif [[ "$src_exists" == "false" ]]; then
                status="TARGET_ONLY"
            elif [[ "$tgt_exists" == "false" ]]; then
                status="SOURCE_ONLY"
            elif [[ "$src_restricted" == "true" && "$tgt_restricted" == "true" ]]; then
                status="RESTRICTED_BOTH"
            elif [[ "$src_restricted" == "true" ]]; then
                status="SOURCE_RESTRICTED"
            elif [[ "$tgt_restricted" == "true" ]]; then
                status="TARGET_RESTRICTED"
            elif [[ "$src_count" -eq 0 && "$tgt_count" -eq 0 ]]; then
                # Provider exists in both but no SKUs - still a match
                status="AVAILABLE_NO_SKUS"
            else
                # Defer final status to jq where zone-aware effective counts are computed
                status="__DEFERRED__"
            fi
            
            # Write SKU JSON to temp files to avoid command-line argument size limits
            local src_skus_file tgt_skus_file
            # Use a non-.json suffix so these don't get picked up by the final assembly glob
            src_skus_file="${temp_dir}/${provider_idx}_src_skus.jqtmp"
            tgt_skus_file="${temp_dir}/${provider_idx}_tgt_skus.jqtmp"
            printf '%s' "$src_skus" > "$src_skus_file"
            printf '%s' "$tgt_skus" > "$tgt_skus_file"

            # Read AZ flags from exported env vars
            local src_has_zones="${__SC_SRC_HAS_ZONES:-unknown}"
            local tgt_has_zones="${__SC_TGT_HAS_ZONES:-unknown}"

            # Write JSON object with zone-aware SKU annotations.
            # SKUs whose names contain ZRS/GZRS/RAGZRS patterns are marked as
            # requiresZones=true. In regions without AZs these are flagged as
            # effectivelyUnavailable so effective counts and status reflect
            # the real usable SKU set.
            jq -n \
                --arg provider "$provider" \
                --arg raw_status "$status" \
                --arg src_region "$source_region" \
                --arg tgt_region "$target_region" \
                --argjson src_types "$src_types" \
                --argjson tgt_types "$tgt_types" \
                --arg src_note "$src_note" \
                --arg tgt_note "$tgt_note" \
                --arg src_has_zones "$src_has_zones" \
                --arg tgt_has_zones "$tgt_has_zones" \
                --slurpfile src_skus "$src_skus_file" \
                --slurpfile tgt_skus "$tgt_skus_file" \
                '
                # Detect SKU names that imply zone-redundancy
                def needs_zones: (.name // "") | test("(?i)(^|_)(G?Z|RAG?Z)RS($|_)");

                # Annotate a SKU array with zone metadata
                def annotate(has_zones):
                    [ .[] | . + {
                        requiresZones: needs_zones,
                        effectivelyUnavailable: (needs_zones and (has_zones == "false"))
                    }];

                ($src_skus[0] | annotate($src_has_zones)) as $src_ann |
                ($tgt_skus[0] | annotate($tgt_has_zones)) as $tgt_ann |
                ([$src_ann[] | select(.effectivelyUnavailable != true)] | length) as $src_eff |
                ([$tgt_ann[] | select(.effectivelyUnavailable != true)] | length) as $tgt_eff |
                ([$src_ann[] | select(.requiresZones == true)] | length) as $src_zone_dep |
                ([$tgt_ann[] | select(.requiresZones == true)] | length) as $tgt_zone_dep |

                # Compute status: use effective counts when zones are known
                (if $raw_status != "__DEFERRED__" then $raw_status
                 elif $src_eff == $tgt_eff then "FULL_MATCH"
                 elif $src_eff > $tgt_eff then "SOURCE_EXTENDED"
                 else "TARGET_EXTENDED"
                 end) as $status |

                {
                    provider: $provider,
                    status: $status,
                    sourceRegion: {
                        name: $src_region,
                        regionHasAvailabilityZones: $src_has_zones,
                        resourceTypes: $src_types,
                        skuCount: ($src_ann | length),
                        effectiveSkuCount: $src_eff,
                        zoneDependentSkuCount: $src_zone_dep,
                        note: (if ($src_note|length) > 0 then $src_note else null end),
                        skus: $src_ann
                    },
                    targetRegion: {
                        name: $tgt_region,
                        regionHasAvailabilityZones: $tgt_has_zones,
                        resourceTypes: $tgt_types,
                        skuCount: ($tgt_ann | length),
                        effectiveSkuCount: $tgt_eff,
                        zoneDependentSkuCount: $tgt_zone_dep,
                        note: (if ($tgt_note|length) > 0 then $tgt_note else null end),
                        skus: $tgt_ann
                    }
                }' > "${temp_dir}/${provider_idx}.json" 2>/dev/null || {
                log_warning "Failed to assemble JSON for provider $provider; emitting minimal record"
                jq -n \
                    --arg provider "$provider" \
                    --arg status "$status" \
                    --arg src_region "$source_region" \
                    --arg tgt_region "$target_region" \
                    --argjson src_types "$src_types" \
                    --argjson tgt_types "$tgt_types" \
                    --argjson src_count "$src_count" \
                    --argjson tgt_count "$tgt_count" \
                    '{
                        provider: $provider,
                        status: $status,
                        sourceRegion: { name: $src_region, resourceTypes: $src_types, skuCount: $src_count, skus: [] },
                        targetRegion: { name: $tgt_region, resourceTypes: $tgt_types, skuCount: $tgt_count, skus: [] },
                        note: "SKU details omitted due to JSON assembly failure"
                    }' > "${temp_dir}/${provider_idx}.json"
            }
        ) &
    done
    
    # Wait for all background jobs to complete
    log_info "[INFO] Waiting for all parallel jobs to complete..."
    wait
    
    log_info "[STEP 5/5] Assembling final outputs (JSON first, CSV from JSON)..."
    
    # Assemble JSON first (source of truth)
    # Only include the per-provider object files ("1.json", "2.json", ...)
    find "$temp_dir" -maxdepth 1 -type f -name '[0-9]*.json' -print0 \
        | sort -z \
        | xargs -0 cat 2>/dev/null \
        | jq -s '.' > "$json_file"

    enrich_provider_comparison_json "$json_file" "$source_region" "$target_region"
    
    # Generate CSV from JSON
    {
        echo "Provider,SKU,ResourceType,SourceHasSKU,TargetHasSKU,SourceSKUCount,TargetSKUCount,SourceEffectiveSKUCount,TargetEffectiveSKUCount,SourceResourceTypes,TargetResourceTypes,Status,RequiresZones,SourceEffectivelyUnavailable,TargetEffectivelyUnavailable,CuratedService,CuratedFamily,CuratedCapabilityCount,SourceZoneSupport,TargetZoneSupport,SourceRegionHasZones,TargetRegionHasZones"
        jq -r '
            def short_provider(p): p | sub("^[Mm]icrosoft\\."; "");
            def sku_key(s): (s.resourceType // "unknown") + ":" + (s.name // "");

            # For providers with no SKUs, emit a single placeholder row.
            # In that case, SourceHasSKU/TargetHasSKU are treated as "provider exists in region"
            # derived from Status, not from SKU presence.
            def src_present(status): (status != "NOT_AVAILABLE" and status != "TARGET_ONLY");
            def tgt_present(status): (status != "NOT_AVAILABLE" and status != "SOURCE_ONLY");

            .[] as $p |
            short_provider($p.provider) as $short |
            ($p.sourceRegion.skus // []) as $src |
            ($p.targetRegion.skus // []) as $tgt |

            # Build union of SKU entries across regions with presence and zone flags
            ((
                ($src | map({key: sku_key(.), name: (.name // ""), resourceType: (.resourceType // ""), requiresZones: (.requiresZones // false), srcEffUnavail: (.effectivelyUnavailable // false), tgtEffUnavail: false, source: true, target: false}))
                +
                ($tgt | map({key: sku_key(.), name: (.name // ""), resourceType: (.resourceType // ""), requiresZones: (.requiresZones // false), srcEffUnavail: false, tgtEffUnavail: (.effectivelyUnavailable // false), source: false, target: true}))
            ) | if length == 0 then [{key: "__no_skus__", name: "", resourceType: "", requiresZones: false, srcEffUnavail: false, tgtEffUnavail: false, source: src_present($p.status), target: tgt_present($p.status)}] else . end)
            | group_by(.key)
            | map({
                provider: $short,
                sku: (.[0].name),
                resourceType: (.[0].resourceType),
                sourceHasSKU: (any(.[]; .source)),
                targetHasSKU: (any(.[]; .target)),
                sourceSKUCount: $p.sourceRegion.skuCount,
                targetSKUCount: $p.targetRegion.skuCount,
                sourceEffectiveSKUCount: ($p.sourceRegion.effectiveSkuCount // $p.sourceRegion.skuCount),
                targetEffectiveSKUCount: ($p.targetRegion.effectiveSkuCount // $p.targetRegion.skuCount),
                sourceResourceTypes: $p.sourceRegion.resourceTypes,
                targetResourceTypes: $p.targetRegion.resourceTypes,
                    status: $p.status,
                    requiresZones: (any(.[]; .requiresZones)),
                    srcEffUnavail: (any(.[]; .srcEffUnavail)),
                    tgtEffUnavail: (any(.[]; .tgtEffUnavail)),
                    curatedService: ($p.curated.displayName // ""),
                    curatedFamily: ($p.curated.family // ""),
                    curatedCapabilityCount: ($p.curated.summaryStats.capabilityCount // 0),
                    sourceZoneSupport: ($p.curated.sourceRegion.zoneSupport.mode // ""),
                    targetZoneSupport: ($p.curated.targetRegion.zoneSupport.mode // ""),
                    sourceRegionHasZones: ($p.sourceRegion.regionHasAvailabilityZones // $p.curated.sourceRegion.regionHasAvailabilityZones // "unknown"),
                    targetRegionHasZones: ($p.targetRegion.regionHasAvailabilityZones // $p.curated.targetRegion.regionHasAvailabilityZones // "unknown")
            })
            | .[]
            | [
                .provider,
                .sku,
                .resourceType,
                (if .sourceHasSKU then "true" else "false" end),
                (if .targetHasSKU then "true" else "false" end),
                .sourceSKUCount,
                .targetSKUCount,
                .sourceEffectiveSKUCount,
                .targetEffectiveSKUCount,
                .sourceResourceTypes,
                .targetResourceTypes,
                    .status,
                    (if .requiresZones then "true" else "false" end),
                    (if .srcEffUnavail then "true" else "false" end),
                    (if .tgtEffUnavail then "true" else "false" end),
                    .curatedService,
                    .curatedFamily,
                    .curatedCapabilityCount,
                    .sourceZoneSupport,
                    .targetZoneSupport,
                    .sourceRegionHasZones,
                    .targetRegionHasZones
            ] | @csv
        ' "$json_file" | sort
    } > "$csv_file"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_info "JSON output: $json_file ($(jq '. | length' "$json_file") providers)"
    log_info "CSV output: $csv_file ($(wc -l < "$csv_file") lines)"
}

################################################################################
# Exported functions
################################################################################

export -f get_providers_in_region
export -f get_service_families
export -f get_compute_skus
export -f get_storage_skus
export -f get_database_skus
export -f get_fabric_skus
export -f compare_services
export -f compare_skus
export -f generate_comparison_outputs
