#!/usr/bin/env bash
# ==============================================================================
# Azure Service Catalog - Comprehensive Service-to-Provider Mapping
# ==============================================================================
# This file defines mappings between service categories and Azure resource
# providers for SKU population. Each category maps to one or more providers
# with specific API versions and resource types.
#
# Usage:
#   source lib/service_catalog.sh
#   get_service_providers "compute"
#   get_service_providers "ai"
# ==============================================================================

# ==============================================================================
# Service Category Definitions
# ==============================================================================
# Categories:
#   - compute: Virtual Machines, VM Scale Sets, Dedicated Hosts
#   - storage: Blob, Files, Disks, NetApp
#   - networking: Load Balancers, App Gateway, Firewall, VPN
#   - databases: SQL, PostgreSQL, MySQL, CosmosDB, Redis
#   - analytics: Synapse, Data Factory, Data Explorer
#   - ai: Cognitive Services, OpenAI, Machine Learning
#   - containers: AKS, Container Instances, Container Registry
#   - serverless: Functions, App Service, Logic Apps, Container Apps
#   - monitoring: Log Analytics, Application Insights, Monitoring
#   - integration: Service Bus, Event Hubs, Event Grid
# ==============================================================================

# Declare associative arrays for service mappings
declare -gA SERVICE_PROVIDERS
declare -gA SERVICE_API_VERSIONS
declare -gA SERVICE_RESOURCE_TYPES

# ==============================================================================
# COMPUTE SERVICES
# ==============================================================================
SERVICE_PROVIDERS[compute]="Microsoft.Compute"
SERVICE_API_VERSIONS[Microsoft.Compute]="2024-03-01"
SERVICE_RESOURCE_TYPES[Microsoft.Compute]="virtualMachines,virtualMachineScaleSets,disks,snapshots"

# ==============================================================================
# STORAGE SERVICES
# ==============================================================================
SERVICE_PROVIDERS[storage]="Microsoft.Storage"
SERVICE_API_VERSIONS[Microsoft.Storage]="2023-01-01"
SERVICE_RESOURCE_TYPES[Microsoft.Storage]="storageAccounts"

# ==============================================================================
# NETWORKING SERVICES
# ==============================================================================
SERVICE_PROVIDERS[networking]="Microsoft.Network"
SERVICE_API_VERSIONS[Microsoft.Network]="2024-01-01"
SERVICE_RESOURCE_TYPES[Microsoft.Network]="loadBalancers,applicationGateways,azureFirewalls,vpnGateways,publicIPAddresses,natGateways"

# ==============================================================================
# DATABASE SERVICES (Multiple Providers)
# ==============================================================================
SERVICE_PROVIDERS[databases]="Microsoft.Sql Microsoft.DBforPostgreSQL Microsoft.DBforMySQL Microsoft.DocumentDB Microsoft.Cache"
SERVICE_API_VERSIONS[Microsoft.Sql]="2023-05-01-preview"
SERVICE_API_VERSIONS[Microsoft.DBforPostgreSQL]="2024-12-30"
SERVICE_API_VERSIONS[Microsoft.DBforMySQL]="2024-12-30"
SERVICE_API_VERSIONS[Microsoft.DocumentDB]="2024-05-15"
SERVICE_API_VERSIONS[Microsoft.Cache]="2023-08-01"
SERVICE_RESOURCE_TYPES[Microsoft.Sql]="servers,managedInstances,elasticPools"
SERVICE_RESOURCE_TYPES[Microsoft.DBforPostgreSQL]="flexibleServers,serverGroupsv2"
SERVICE_RESOURCE_TYPES[Microsoft.DBforMySQL]="flexibleServers"
SERVICE_RESOURCE_TYPES[Microsoft.DocumentDB]="databaseAccounts,cassandraClusters,mongoClusters"
SERVICE_RESOURCE_TYPES[Microsoft.Cache]="redis,redisEnterprise"

# ==============================================================================
# ANALYTICS/FABRIC SERVICES (Multiple Providers)
# ==============================================================================
SERVICE_PROVIDERS[analytics]="Microsoft.Synapse Microsoft.DataFactory Microsoft.Kusto Microsoft.Databricks"
SERVICE_API_VERSIONS[Microsoft.Synapse]="2021-06-01"
SERVICE_API_VERSIONS[Microsoft.DataFactory]="2018-06-01"
SERVICE_API_VERSIONS[Microsoft.Kusto]="2023-08-15"
SERVICE_API_VERSIONS[Microsoft.Databricks]="2023-02-01"
SERVICE_RESOURCE_TYPES[Microsoft.Synapse]="workspaces,sqlPools,bigDataPools,kustoPools"
SERVICE_RESOURCE_TYPES[Microsoft.DataFactory]="factories,integrationRuntimes"
SERVICE_RESOURCE_TYPES[Microsoft.Kusto]="clusters"
SERVICE_RESOURCE_TYPES[Microsoft.Databricks]="workspaces"

# ==============================================================================
# AI SERVICES (Multiple Providers)
# ==============================================================================
SERVICE_PROVIDERS[ai]="Microsoft.CognitiveServices Microsoft.MachineLearningServices"
SERVICE_API_VERSIONS[Microsoft.CognitiveServices]="2024-04-01-preview"
SERVICE_API_VERSIONS[Microsoft.MachineLearningServices]="2024-04-01"
SERVICE_RESOURCE_TYPES[Microsoft.CognitiveServices]="accounts,commitmentPlans"
SERVICE_RESOURCE_TYPES[Microsoft.MachineLearningServices]="workspaces,computeInstances,computeClusters"

# ==============================================================================
# CONTAINER SERVICES (Multiple Providers)
# ==============================================================================
SERVICE_PROVIDERS[containers]="Microsoft.ContainerService Microsoft.ContainerRegistry Microsoft.ContainerInstance"
SERVICE_API_VERSIONS[Microsoft.ContainerService]="2024-05-01"
SERVICE_API_VERSIONS[Microsoft.ContainerRegistry]="2023-11-01-preview"
SERVICE_API_VERSIONS[Microsoft.ContainerInstance]="2023-05-01"
SERVICE_RESOURCE_TYPES[Microsoft.ContainerService]="managedClusters,agentPools,snapshots"
SERVICE_RESOURCE_TYPES[Microsoft.ContainerRegistry]="registries"
SERVICE_RESOURCE_TYPES[Microsoft.ContainerInstance]="containerGroups"

# ==============================================================================
# SERVERLESS SERVICES (Multiple Providers)
# ==============================================================================
SERVICE_PROVIDERS[serverless]="Microsoft.Web Microsoft.App"
SERVICE_API_VERSIONS[Microsoft.Web]="2023-01-01"
SERVICE_API_VERSIONS[Microsoft.App]="2024-03-01"
SERVICE_RESOURCE_TYPES[Microsoft.Web]="serverfarms,sites,functionApps,staticSites"
SERVICE_RESOURCE_TYPES[Microsoft.App]="containerApps,managedEnvironments"

# ==============================================================================
# MONITORING SERVICES (Multiple Providers)
# ==============================================================================
SERVICE_PROVIDERS[monitoring]="Microsoft.OperationalInsights Microsoft.Insights"
SERVICE_API_VERSIONS[Microsoft.OperationalInsights]="2023-09-01"
SERVICE_API_VERSIONS[Microsoft.Insights]="2023-01-01"
SERVICE_RESOURCE_TYPES[Microsoft.OperationalInsights]="workspaces,clusters"
SERVICE_RESOURCE_TYPES[Microsoft.Insights]="components,actionGroups,webtests"

# ==============================================================================
# INTEGRATION SERVICES
# ==============================================================================
SERVICE_PROVIDERS[integration]="Microsoft.ServiceBus Microsoft.EventHub Microsoft.EventGrid"
SERVICE_API_VERSIONS[Microsoft.ServiceBus]="2022-10-01-preview"
SERVICE_API_VERSIONS[Microsoft.EventHub]="2024-01-01"
SERVICE_API_VERSIONS[Microsoft.EventGrid]="2024-06-01-preview"
SERVICE_RESOURCE_TYPES[Microsoft.ServiceBus]="namespaces"
SERVICE_RESOURCE_TYPES[Microsoft.EventHub]="namespaces,clusters"
SERVICE_RESOURCE_TYPES[Microsoft.EventGrid]="topics,domains"

# ==============================================================================
# Helper Functions
# ==============================================================================

# Get all providers for a service category
get_service_providers() {
    local category="$1"
    
    if [[ -z "$category" ]]; then
        log_error "get_service_providers: category required"
        return 1
    fi
    
    local providers="${SERVICE_PROVIDERS[$category]}"
    
    if [[ -z "$providers" ]]; then
        log_warning "No providers defined for category: $category"
        return 1
    fi
    
    echo "$providers"
    return 0
}

# Get API version for a specific provider
get_provider_api_version() {
    local provider="$1"
    
    if [[ -z "$provider" ]]; then
        log_error "get_provider_api_version: provider required"
        return 1
    fi
    
    local api_version="${SERVICE_API_VERSIONS[$provider]}"
    
    if [[ -z "$api_version" ]]; then
        # Default fallback
        api_version="2021-06-01"
        log_warning "No API version defined for $provider, using default: $api_version"
    fi
    
    echo "$api_version"
    return 0
}

# Get resource types for a provider
get_provider_resource_types() {
    local provider="$1"
    
    if [[ -z "$provider" ]]; then
        log_error "get_provider_resource_types: provider required"
        return 1
    fi
    
    local resource_types="${SERVICE_RESOURCE_TYPES[$provider]}"
    
    if [[ -z "$resource_types" ]]; then
        log_warning "No resource types defined for $provider"
        return 1
    fi
    
    echo "$resource_types"
    return 0
}

# List all available service categories
list_service_categories() {
    echo "${!SERVICE_PROVIDERS[@]}" | tr ' ' '\n' | sort
}

# Get human-readable category name
get_category_display_name() {
    local category="$1"
    
    case "$category" in
        compute) echo "Compute (VMs, VM Scale Sets)" ;;
        storage) echo "Storage (Blob, Files, Disks)" ;;
        networking) echo "Networking (Load Balancers, Firewall, VPN)" ;;
        databases) echo "Databases (SQL, PostgreSQL, MySQL, CosmosDB)" ;;
        analytics) echo "Analytics/Fabric (Synapse, Data Factory)" ;;
        ai) echo "AI Services (Cognitive Services, OpenAI, ML)" ;;
        containers) echo "Containers (AKS, ACR, ACI)" ;;
        serverless) echo "Serverless (Functions, App Service, Container Apps)" ;;
        monitoring) echo "Monitoring (Log Analytics, App Insights)" ;;
        integration) echo "Integration (Service Bus, Event Hub)" ;;
        *) echo "$category" ;;
    esac
}

# Validate that all required service mappings are present
validate_service_catalog() {
    local errors=0
    
    log_info "Validating service catalog..."
    
    for category in "${!SERVICE_PROVIDERS[@]}"; do
        local providers="${SERVICE_PROVIDERS[$category]}"
        
        for provider in $providers; do
            # Check API version
            if [[ -z "${SERVICE_API_VERSIONS[$provider]}" ]]; then
                log_warning "Missing API version for provider: $provider (category: $category)"
                ((errors++))
            fi
            
            # Check resource types
            if [[ -z "${SERVICE_RESOURCE_TYPES[$provider]}" ]]; then
                log_warning "Missing resource types for provider: $provider (category: $category)"
                ((errors++))
            fi
        done
    done
    
    if [[ $errors -eq 0 ]]; then
        log_success "Service catalog validation passed"
        return 0
    else
        log_error "Service catalog validation failed with $errors errors"
        return 1
    fi
}

# Print service catalog summary
print_service_catalog() {
    echo "=================================================="
    echo "Azure Service Catalog"
    echo "=================================================="
    echo ""
    
    for category in $(list_service_categories); do
        local display_name=$(get_category_display_name "$category")
        local providers="${SERVICE_PROVIDERS[$category]}"
        
        echo "[$category] $display_name"
        
        for provider in $providers; do
            local api_version="${SERVICE_API_VERSIONS[$provider]}"
            local resource_types="${SERVICE_RESOURCE_TYPES[$provider]}"
            
            echo "  → Provider: $provider"
            echo "    API Version: $api_version"
            echo "    Resource Types: $resource_types"
        done
        
        echo ""
    done
}

# Export functions for use in other scripts
export -f get_service_providers
export -f get_provider_api_version
export -f get_provider_resource_types
export -f list_service_categories
export -f get_category_display_name
export -f validate_service_catalog
export -f print_service_catalog

# Validate catalog on load (optional, can be disabled for performance)
if [[ "${VALIDATE_SERVICE_CATALOG:-true}" == "true" ]]; then
    validate_service_catalog || true
fi
