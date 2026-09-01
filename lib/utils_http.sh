#!/usr/bin/env bash
# ==============================================================================
# HTTP Utilities - Retry Logic and Pagination
# ==============================================================================

# Retry configuration
MAX_RETRIES=3
INITIAL_BACKOFF=2

# ==============================================================================
# HTTP GET with retry and exponential backoff
# ==============================================================================
http_get_with_retry() {
    local url="$1"
    local max_retries="${2:-$MAX_RETRIES}"
    local retry_count=0
    local backoff=$INITIAL_BACKOFF
    
    while [[ $retry_count -lt $max_retries ]]; do
        local response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
        local http_code=$(echo "$response" | tail -n1)
        local body=$(echo "$response" | sed '$d')
        
        if [[ "$http_code" == "200" ]]; then
            increment_api_call
            echo "$body"
            return 0
        elif [[ "$http_code" == "429" ]] || [[ "$http_code" =~ ^5 ]]; then
            ((retry_count++))
            log_warning "HTTP $http_code received. Retry $retry_count/$max_retries after ${backoff}s"
            sleep $backoff
            backoff=$((backoff * 2))
        else
            log_error "HTTP request failed with code $http_code: $url"
            return 1
        fi
    done
    
    log_error "Max retries exceeded for: $url"
    return 1
}

# ==============================================================================
# Paginate through Azure Retail Prices API
# ==============================================================================
fetch_all_pages() {
    local base_url="$1"
    local all_results="[]"
    local next_page_url="$base_url"
    local page_count=0
    
    while [[ -n "$next_page_url" ]]; do
        ((page_count++))
        log_debug "Fetching page $page_count: $next_page_url"
        
        local response=$(http_get_with_retry "$next_page_url")
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to fetch page $page_count"
            return 1
        fi
        
        # Extract items and append to results
        local items=$(echo "$response" | jq -c '.Items // []')
        all_results=$(echo "$all_results" | jq -c ". + $items")
        
        # Get next page URL
        next_page_url=$(echo "$response" | jq -r '.NextPageLink // empty')
        
        if [[ -z "$next_page_url" ]]; then
            log_debug "No more pages (total pages: $page_count)"
            break
        fi
    done
    
    echo "$all_results"
    return 0
}

# ==============================================================================
# Build OData filter for Retail Prices API
# ==============================================================================
build_pricing_filter() {
    local service_name="$1"
    local region="$2"
    local sku_name="$3"
    
    local filter="armRegionName eq '$region'"
    
    if [[ -n "$service_name" ]]; then
        filter="$filter and serviceName eq '$service_name'"
    fi
    
    if [[ -n "$sku_name" ]]; then
        filter="$filter and armSkuName eq '$sku_name'"
    fi
    
    echo "$filter"
}

# ==============================================================================
# URL encode string
# ==============================================================================
url_encode() {
    local string="$1"
    echo "$string" | jq -sRr @uri
}
