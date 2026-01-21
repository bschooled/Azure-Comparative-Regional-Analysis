#!/usr/bin/env bash
# ==============================================================================
# Region Name Mapping and Fuzzy Matching
# ==============================================================================

REGIONS_CACHE="${CACHE_DIR}/azure_regions.json"

# ==============================================================================
# Fetch and cache list of all Azure regions
# ==============================================================================
fetch_azure_regions() {
    # Check if cache exists, is valid, and has content
    if is_cache_valid "$REGIONS_CACHE" 2>/dev/null && [[ -s "$REGIONS_CACHE" ]]; then
        return 0
    fi
    
    log_info "Fetching list of available Azure regions..." >&2
    
    if az account list-locations --output json > "$REGIONS_CACHE" 2>> "${LOG_FILE:-/dev/null}"; then
        local region_count=$(jq '. | length' "$REGIONS_CACHE" 2>/dev/null || echo 0)
        log_success "Retrieved $region_count Azure regions" >&2
        increment_api_call 2>/dev/null
        return 0
    else
        log_error "Failed to fetch Azure regions" >&2
        return 1
    fi
}

# ==============================================================================
# Calculate simple edit distance for fuzzy matching (optimized for performance)
# ==============================================================================
simple_distance() {
    local str1="${1,,}"
    local str2="${2,,}"
    
    # Exact substring match gets priority (distance 0)
    if [[ "$str2" == *"$str1"* ]] || [[ "$str1" == *"$str2"* ]]; then
        echo 0
        return 0
    fi
    
    # Token-based matching: if any significant word matches
    local tokens1=(${str1// / })
    local tokens2=(${str2// / })
    
    local matches=0
    for token1 in "${tokens1[@]}"; do
        for token2 in "${tokens2[@]}"; do
            if [[ "$token1" == "$token2" ]]; then
                ((matches++))
            fi
        done
    done
    
    # If we got matches, return distance based on how many matched
    if [[ $matches -gt 0 ]]; then
        local total_tokens=$((${#tokens1[@]} + ${#tokens2[@]}))
        local distance=$((total_tokens - (matches * 2)))
        [[ $distance -lt 0 ]] && distance=0
        echo $distance
        return 0
    fi
    
    # Fallback to length difference
    local len1=${#str1}
    local len2=${#str2}
    local diff=$((len1 - len2))
    [[ $diff -lt 0 ]] && diff=$((-diff))
    echo $diff
}

# ==============================================================================
# Find best matching region
# ==============================================================================
find_best_region_match() {
    local user_input="$1"
    
    if [[ ! -f "$REGIONS_CACHE" ]]; then
        log_error "Regions cache not found"
        return 1
    fi
    
    local input_lower="${user_input,,}"
    local best_match=""
    local best_score=0
    local best_display_name=""
    
    # Try exact matches first (case-insensitive)
    while IFS= read -r region_json; do
        local name=$(echo "$region_json" | jq -r '.name' 2>/dev/null)
        local display=$(echo "$region_json" | jq -r '.displayName' 2>/dev/null)
        
        if [[ "${name,,}" == "$input_lower" || "${display,,}" == "$input_lower" ]]; then
            echo "$name"
            return 0
        fi
    done < <(jq -c '.[]' "$REGIONS_CACHE")
    
    # Fuzzy matching on region names and display names
    while IFS= read -r region_json; do
        local name=$(echo "$region_json" | jq -r '.name' 2>/dev/null)
        local display=$(echo "$region_json" | jq -r '.displayName' 2>/dev/null)
        
        # Token-based scoring
        local tokens_input=(${input_lower// / })
        local tokens_name=(${name,,//\// })  # Replace / with space for compound names
        local tokens_display=(${display,,// / })
        
        local score_name=0
        local score_display=0
        
        # Count token matches
        for token_input in "${tokens_input[@]}"; do
            for token_name in "${tokens_name[@]}"; do
                if [[ "$token_input" == "$token_name" ]]; then
                    ((score_name++))
                fi
            done
            for token_display in "${tokens_display[@]}"; do
                if [[ "$token_input" == "$token_display" ]]; then
                    ((score_display++))
                fi
            done
        done
        
        # Use the higher score, but add bonus for substring matches
        local score=$score_name
        [[ $score_display -gt $score ]] && score=$score_display
        
        # Bonus if display name contains input as substring
        if [[ "${display,,}" == *"${input_lower}"* ]] || [[ "${input_lower}" == *"${display,,}"* ]]; then
            score=$((score + 5))
        fi
        
        if [[ $score -gt $best_score ]]; then
            best_score=$score
            best_match="$name"
            best_display_name="$display"
        fi
    done < <(jq -c '.[]' "$REGIONS_CACHE")
    
    # Only return if we found a reasonable match (score > 0)
    if [[ $best_score -gt 0 && -n "$best_match" ]]; then
        echo "$best_match"
        return 0
    fi
    
    log_error "No matching region found for: $user_input"
    return 1
}

# ==============================================================================
# Confirm region with user
# ==============================================================================
confirm_region() {
    local user_input="$1"
    local matched_region="$2"
    
    if [[ "${user_input,,}" == "${matched_region,,}" ]]; then
        # Exact match, no confirmation needed
        return 0
    fi
    
    # Get display name for the matched region
    local display_name=$(jq -r ".[] | select(.name == \"$matched_region\") | .displayName" "$REGIONS_CACHE" 2>/dev/null)
    
    # Check if stdin is a TTY (interactive mode)
    if [[ ! -t 0 ]]; then
        # Non-interactive mode: just log and proceed without asking
        log_info "Region resolved: '$user_input' → '$matched_region' ($display_name)" >&2
        return 0
    fi
    
    # Interactive mode: ask for confirmation
    echo "" >&2
    echo "❓ Did you mean: $matched_region ($display_name)?" >&2
    echo "   You entered:  $user_input" >&2
    echo "" >&2
    
    # Use read with a timeout to avoid hanging
    if read -t 10 -p "Proceed with '$matched_region'? (y/n) " -n 1 -r <&2; then
        echo >&2
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            return 0
        else
            log_error "Region not confirmed by user" >&2
            return 1
        fi
    else
        # Timeout or no input, proceed with match in non-interactive
        echo "" >&2
        log_info "No input received; proceeding with matched region" >&2
        return 0
    fi
}

# ==============================================================================
# Resolve region input to region code
# ==============================================================================
resolve_region() {
    local user_input="$1"
    
    if [[ -z "$user_input" ]]; then
        return 1
    fi
    
    # Fetch available regions if needed
    if ! fetch_azure_regions; then
        log_warning "Could not fetch Azure regions; proceeding with user input" 2>/dev/null
        echo "$user_input"
        return 0
    fi
    
    # Find best match
    local matched_region=$(find_best_region_match "$user_input")
    if [[ -z "$matched_region" ]]; then
        log_error "Could not find a region matching: $user_input"
        return 1
    fi
    
    # Confirm with user
    if ! confirm_region "$user_input" "$matched_region"; then
        return 1
    fi
    
    echo "$matched_region"
    return 0
}

# ==============================================================================
# List all available regions
# ==============================================================================
list_regions() {
    if [[ ! -f "$REGIONS_CACHE" ]]; then
        log_error "Regions cache not available"
        return 1
    fi
    
    log_info "Available Azure Regions:"
    echo ""
    jq -r '.[] | "\(.name | @json) - \(.displayName)"' "$REGIONS_CACHE" | sort | sed 's/"//g' | column -t -s ' - '
}
