#!/usr/bin/env bash
# ==============================================================================
# Caching Utilities
# ==============================================================================

# Cache TTL in seconds (default: 24 hours)
CACHE_TTL=${CACHE_TTL:-86400}

# Initialize cache directory
init_cache() {
    CACHE_DIR="${1:-${CACHE_DIR:-.cache}}"
    mkdir -p "${CACHE_DIR}"
}

# ==============================================================================
# Generate cache key from content
# ==============================================================================
cache_key() {
    local content="${1:-}"
    
    # If no argument provided, read from stdin (for piped input)
    if [[ -z "$content" ]]; then
        content=$(cat)
    fi
    
    # Generate hash
    echo -n "$content" | sha256sum | awk '{print $1}'
}

# ==============================================================================
# Check if cache file exists and is valid
# ==============================================================================
is_cache_valid() {
    local cache_file="${1:-}"
    local ttl="${2:-$CACHE_TTL}"
    
    if [[ -z "$cache_file" ]] || [[ ! -f "$cache_file" ]]; then
        return 1
    fi
    
    local current_time=$(date +%s)
    local file_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    local age=$((current_time - file_time))
    
    if [[ $age -gt $ttl ]]; then
        log_debug "Cache expired: $cache_file (age: ${age}s, TTL: ${ttl}s)"
        return 1
    fi
    
    return 0
}

# ==============================================================================
# Get cached data
# ==============================================================================
get_cache() {
    local cache_key="$1"
    local ttl="${2:-$CACHE_TTL}"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    
    if is_cache_valid "$cache_file" "$ttl"; then
        log_debug "Cache hit: $cache_key"
        increment_cache_hit
        cat "$cache_file"
        return 0
    fi
    
    log_debug "Cache miss: $cache_key"
    return 1
}

# ==============================================================================
# Save data to cache
# ==============================================================================
set_cache() {
    local cache_key="$1"
    local data="$2"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    
    mkdir -p "${CACHE_DIR}"
    echo "$data" > "$cache_file"
    log_debug "Cached data: $cache_key"
}

# Backwards-compatible helpers used by service_comparison.sh
check_cache() {
    local cache_key="$1"
    local ttl="${2:-$CACHE_TTL}"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    is_cache_valid "$cache_file" "$ttl"
}

read_cache() {
    local cache_key="$1"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    cat "$cache_file"
}

write_cache() {
    local cache_key="$1"
    local data="$2"
    local cache_file="${CACHE_DIR}/${cache_key}.json"
    mkdir -p "${CACHE_DIR}"
    echo "$data" > "$cache_file"
}

# ==============================================================================
# Clear cache directory
# ==============================================================================
clear_cache() {
    log_info "Clearing cache directory: ${CACHE_DIR}"
    rm -rf "${CACHE_DIR}"/*
    log_success "Cache cleared"
}

# ==============================================================================
# Get cache statistics
# ==============================================================================
cache_stats() {
    local file_count=$(find "${CACHE_DIR}" -type f -name "*.json" 2>/dev/null | wc -l)
    local cache_size=$(du -sh "${CACHE_DIR}" 2>/dev/null | awk '{print $1}')
    
    log_info "Cache files: $file_count"
    log_info "Cache size: $cache_size"
}
