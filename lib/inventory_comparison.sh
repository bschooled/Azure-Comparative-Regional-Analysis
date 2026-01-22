#!/usr/bin/env bash
# ==============================================================================
# Inventory-based Comparison Output Generation
# ==============================================================================
# Reuses query_provider_skus() from service_comparison.sh for shared caching
# Generates same JSON/CSV format as services_compare.sh
# ==============================================================================

# ==============================================================================
# Generate inventory-based comparison outputs (same format as services_compare.sh)
# ==============================================================================
generate_inventory_comparison_outputs() {
    local source_region="$1"
    local target_region="$2"
    local csv_file="$3"
    local json_file="$4"
    
    log_info "Generating inventory-based comparison outputs..."
    log_info "Source: $source_region, Target: $target_region"
    log_info "Output files: $json_file, $csv_file"
    
    if [[ ! -f "$TUPLES_FILE" ]]; then
        log_error "Tuples file not found: $TUPLES_FILE"
        return 1
    fi
    
    log_info "Reading tuples from: $TUPLES_FILE"
    
    # Extract unique provider namespaces from inventory tuples.
    # Also include synthetic resource-type entries when present (e.g. microsoft.compute/disks).
    local inventory_providers
    inventory_providers=$(jq -r '
        (map(.type | ascii_downcase) | unique) as $types
        | (
            ($types | map(split("/")[0]) | unique)
            + (if ($types | index("microsoft.compute/disks")) then ["microsoft.compute/disks"] else [] end)
          )
        | unique
        | .[]
    ' "$TUPLES_FILE" 2>&1)
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to extract providers from tuples: $inventory_providers"
        return 1
    fi
    
    if [[ -z "$inventory_providers" ]]; then
        log_warning "No providers found in inventory tuples"
        echo "[]" > "$json_file"
        echo "Provider,SKU,ResourceType,SourceHasSKU,TargetHasSKU,SourceSKUCount,TargetSKUCount,SourceResourceTypes,TargetResourceTypes,Status" > "$csv_file"
        return 0
    fi
    
    local provider_count=$(echo "$inventory_providers" | wc -l)
    log_info "Found $provider_count unique providers in inventory"

        # Optional: canonicalize provider namespace casing using the cached provider list
        # (helps align with services_compare.sh cache keys and output naming)
        local providers_cache_path="${PROVIDERS_CACHE:-${CACHE_DIR}/providers.json}"
        declare -A provider_case_map
        if [[ -f "$providers_cache_path" ]] && jq empty "$providers_cache_path" 2>/dev/null; then
            while IFS= read -r ns; do
                [[ -n "$ns" ]] || continue
                provider_case_map["${ns,,}"]="$ns"
            done < <(jq -r '.[].namespace // empty' "$providers_cache_path" 2>/dev/null)
        fi
    
    # Create temp directory for results
    local temp_dir=$(mktemp -d)
    
    log_info "Processing inventory providers sequentially (using shared cache)..."
    
    # Convert to array for proper iteration
    local provider_array
    mapfile -t provider_array <<< "$inventory_providers"
    
    # Process providers sequentially to avoid subshell issues
    local provider_idx=0
    for provider in "${provider_array[@]}"; do
        if [[ -z "$provider" ]]; then
            continue
        fi
        ((provider_idx++))

            local provider_canonical="${provider_case_map[$provider]:-$provider}"
            if [[ "$provider" == "microsoft.compute/disks" ]]; then
                provider_canonical="Microsoft.Compute/disks"
            fi
        
            log_info "[PROVIDER $provider_idx/$provider_count] Processing $provider_canonical (from inventory)"
        
        # Get resource type counts from inventory (since these are actual resources)
        local src_types tgt_types
        if [[ "$provider" == *"/"* ]]; then
            src_types=$(jq --arg provider_lc "$provider" '[.data[]? | select((.type? // "" | ascii_downcase) == $provider_lc) | (.type? // "" | ascii_downcase)] | unique | length' "$INVENTORY_FILE" 2>/dev/null || echo "0")
        else
            src_types=$(jq --arg provider_lc "$provider" '[.data[]? | select((.type? // "" | ascii_downcase) | startswith($provider_lc + "/")) | (.type? // "" | ascii_downcase)] | unique | length' "$INVENTORY_FILE" 2>/dev/null || echo "0")
        fi
        
        # For target, we'll use the same count as source (assumption: same types needed)
        tgt_types="$src_types"
        
        # Query SKUs for this provider in both regions using SHARED cache
            log_info "[SKU QUERY] Querying $provider_canonical SKUs (shared cache)"
        local src_skus tgt_skus src_count tgt_count
            src_skus=$(query_provider_skus "$source_region" "$provider_canonical" 2>/dev/null || echo "[]")
        src_count=$(echo "$src_skus" | jq '. | length' 2>/dev/null || echo "0")
        
            tgt_skus=$(query_provider_skus "$target_region" "$provider_canonical" 2>/dev/null || echo "[]")
        tgt_count=$(echo "$tgt_skus" | jq '. | length' 2>/dev/null || echo "0")
        
            log_info "[SKU RESULT] $provider_canonical: $src_count in $source_region, $tgt_count in $target_region"
        
        # Determine status
        local status
        if [[ "$src_count" -eq 0 && "$tgt_count" -eq 0 ]]; then
            status="AVAILABLE_NO_SKUS"
        elif [[ "$src_count" -eq "$tgt_count" ]]; then
            status="FULL_MATCH"
        elif [[ "$src_count" -gt "$tgt_count" ]]; then
            status="SOURCE_EXTENDED"
        else
            status="TARGET_EXTENDED"
        fi
        
            # Write SKU JSON to temp files to avoid command-line argument size limits
            local src_skus_file tgt_skus_file
            # Use a non-.json suffix so these don't get picked up by the final assembly glob
            src_skus_file="${temp_dir}/${provider_idx}_src_skus.jqtmp"
            tgt_skus_file="${temp_dir}/${provider_idx}_tgt_skus.jqtmp"
            printf '%s' "$src_skus" > "$src_skus_file"
            printf '%s' "$tgt_skus" > "$tgt_skus_file"

            # Write JSON object (load SKUs from files with --slurpfile so large arrays are safe)
            jq -n \
                --arg provider "$provider_canonical" \
                --arg status "$status" \
                --arg src_region "$source_region" \
                --arg tgt_region "$target_region" \
                --argjson src_types "$src_types" \
                --argjson tgt_types "$tgt_types" \
                --slurpfile src_skus "$src_skus_file" \
                --slurpfile tgt_skus "$tgt_skus_file" \
                '{
                    provider: $provider,
                    status: $status,
                    sourceRegion: {
                        name: $src_region,
                        resourceTypes: $src_types,
                        skuCount: ($src_skus[0] | length),
                        skus: $src_skus[0]
                    },
                    targetRegion: {
                        name: $tgt_region,
                        resourceTypes: $tgt_types,
                        skuCount: ($tgt_skus[0] | length),
                        skus: $tgt_skus[0]
                    }
                }' > "${temp_dir}/${provider_idx}.json" 2>/dev/null || {
                log_warning "Failed to assemble JSON for provider $provider_canonical; emitting minimal record"
                jq -n \
                    --arg provider "$provider_canonical" \
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
    done
    
    log_info "Assembling final outputs (JSON first, CSV from JSON)..."
    
    # Assemble JSON first (source of truth)
    # Only include the per-provider object files ("1.json", "2.json", ...)
    find "$temp_dir" -maxdepth 1 -type f -name '[0-9]*.json' -print0 \
        | sort -z \
        | xargs -0 cat 2>/dev/null \
        | jq -s '.' > "$json_file"
    
    # Generate CSV from JSON (same format as services_compare.sh)
    {
        echo "Provider,SKU,ResourceType,SourceHasSKU,TargetHasSKU,SourceSKUCount,TargetSKUCount,SourceResourceTypes,TargetResourceTypes,Status"
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

                # Build union of SKU entries across regions with presence flags
                ((
                    ($src | map({key: sku_key(.), name: (.name // ""), resourceType: (.resourceType // ""), source: true, target: false}))
                    +
                    ($tgt | map({key: sku_key(.), name: (.name // ""), resourceType: (.resourceType // ""), source: false, target: true}))
                ) | if length == 0 then [{key: "__no_skus__", name: "", resourceType: "", source: src_present($p.status), target: tgt_present($p.status)}] else . end)
                | group_by(.key)
                | map({
                    provider: $short,
                    sku: (.[0].name),
                    resourceType: (.[0].resourceType),
                    sourceHasSKU: (any(.[]; .source)),
                    targetHasSKU: (any(.[]; .target)),
                    sourceSKUCount: $p.sourceRegion.skuCount,
                    targetSKUCount: $p.targetRegion.skuCount,
                    sourceResourceTypes: $p.sourceRegion.resourceTypes,
                    targetResourceTypes: $p.targetRegion.resourceTypes,
                    status: $p.status
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
                    .sourceResourceTypes,
                    .targetResourceTypes,
                    .status
                ] | @csv
            ' "$json_file" | sort
    } > "$csv_file"
    
    # Cleanup
    rm -rf "$temp_dir"
    
    log_info "JSON output: $json_file ($(jq '. | length' "$json_file") providers)"
    log_info "CSV output: $csv_file ($(wc -l < "$csv_file") lines)"
}

export -f generate_inventory_comparison_outputs
