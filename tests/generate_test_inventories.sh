#!/usr/bin/env bash
# ==============================================================================
# Test Inventory Generator
# ==============================================================================
# Generates diverse test inventories across multiple Azure resource types
# to validate the generalized SKU provider fetching mechanism

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_ROOT}/test_inventories"

mkdir -p "$OUTPUT_DIR"

# ==============================================================================
# Generate diverse test inventory with multiple provider types
# ==============================================================================
generate_diverse_inventory() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
{
  "metadata": {
    "source_region": "centralus",
    "generated_at": "2026-01-20",
    "description": "Diverse inventory across multiple Azure resource types"
  },
  "resources": [
    {
      "id": "VM001",
      "type": "microsoft.compute/virtualmachines",
      "vmSize": "Standard_B2ms",
      "name": "web-server-01"
    },
    {
      "id": "VM002",
      "type": "microsoft.compute/virtualmachines",
      "vmSize": "Standard_D4s_v3",
      "name": "app-server-01"
    },
    {
      "id": "DISK001",
      "type": "microsoft.compute/disks",
      "diskSku": "Standard_LRS",
      "name": "data-disk-01"
    },
    {
      "id": "DISK002",
      "type": "microsoft.compute/disks",
      "diskSku": "Premium_LRS",
      "name": "premium-disk-01"
    },
    {
      "id": "STORAGE001",
      "type": "microsoft.storage/storageaccounts",
      "sku": "Standard_LRS",
      "name": "storageacc01"
    },
    {
      "id": "AKS001",
      "type": "microsoft.containerservice/managedclusters",
      "vmSize": "Standard_D2s_v3",
      "name": "production-aks-cluster"
    },
    {
      "id": "AKS002",
      "type": "microsoft.containerservice/managedclusters",
      "vmSize": "Standard_B2ms",
      "name": "dev-aks-cluster"
    },
    {
      "id": "POSTGRES001",
      "type": "microsoft.dbforpostgresql/flexibleservers",
      "sku": "Standard_B1ms",
      "name": "postgres-db-01"
    },
    {
      "id": "POSTGRES002",
      "type": "microsoft.dbforpostgresql/flexibleservers",
      "sku": "Standard_D4s_v3",
      "name": "postgres-db-prod"
    },
    {
      "id": "MYSQL001",
      "type": "microsoft.dbformysql/flexibleservers",
      "sku": "Standard_B1ms",
      "name": "mysql-db-01"
    },
    {
      "id": "COSMOS001",
      "type": "microsoft.documentdb/databaseaccounts",
      "kind": "GlobalDocumentDB",
      "name": "cosmos-account-01"
    },
    {
      "id": "COSMOS002",
      "type": "microsoft.documentdb/databaseaccounts",
      "kind": "MongoDB",
      "name": "cosmos-mongodb-01"
    },
    {
      "id": "OPENAI001",
      "type": "microsoft.cognitiveservices/accounts",
      "kind": "OpenAI",
      "sku": "S0",
      "name": "openai-account-01"
    },
    {
      "id": "AI_FORM001",
      "type": "microsoft.cognitiveservices/accounts",
      "kind": "FormRecognizer",
      "sku": "S0",
      "name": "form-recognizer-01"
    },
    {
      "id": "AI_VISION001",
      "type": "microsoft.cognitiveservices/accounts",
      "kind": "ComputerVision",
      "sku": "S1",
      "name": "cv-account-01"
    },
    {
      "id": "MLWS001",
      "type": "microsoft.machinelearningservices/workspaces",
      "name": "ml-workspace-foundry"
    },
    {
      "id": "MLCMP001",
      "type": "microsoft.machinelearningservices/workspaces/computes",
      "sku": "STANDARD_DS3_V2",
      "name": "ml-compute-cluster"
    },
    {
      "id": "FUNCTION001",
      "type": "microsoft.web/serverfarms",
      "sku": "EP1",
      "name": "functions-premium-plan"
    },
    {
      "id": "FUNCTION002",
      "type": "microsoft.web/serverfarms",
      "sku": "B1",
      "name": "functions-basic-plan"
    },
    {
      "id": "APPSERVICE001",
      "type": "microsoft.web/serverfarms",
      "sku": "S1",
      "name": "web-app-standard"
    },
    {
      "id": "REDIS001",
      "type": "microsoft.cache/redis",
      "sku": "Standard",
      "size": "c0",
      "name": "cache-01"
    },
    {
      "id": "REDIS002",
      "type": "microsoft.cache/redis",
      "sku": "Premium",
      "size": "p1",
      "name": "cache-premium"
    },
    {
      "id": "SQL001",
      "type": "microsoft.sql/servers",
      "name": "sql-server-01"
    },
    {
      "id": "SQLDB001",
      "type": "microsoft.sql/servers/databases",
      "sku": "Standard",
      "name": "business-database"
    },
    {
      "id": "KEYVAULT001",
      "type": "microsoft.keyvault/vaults",
      "sku": "Standard",
      "name": "kv-prod-01"
    },
    {
      "id": "APPINSIGHTS001",
      "type": "microsoft.insights/components",
      "name": "app-insights-01"
    },
    {
      "id": "EVENTGRID001",
      "type": "microsoft.eventgrid/topics",
      "sku": "Basic",
      "name": "event-topic-01"
    },
    {
      "id": "EVENTHUB001",
      "type": "microsoft.eventhub/namespaces",
      "sku": "Standard",
      "name": "eventhub-namespace-01"
    },
    {
      "id": "SERVICEBUS001",
      "type": "microsoft.servicebus/namespaces",
      "sku": "Standard",
      "name": "servicebus-namespace-01"
    },
    {
      "id": "DATABRICKS001",
      "type": "microsoft.databricks/workspaces",
      "sku": "Standard",
      "name": "databricks-ws-01"
    },
    {
      "id": "SYNAPSE001",
      "type": "microsoft.synapse/workspaces",
      "name": "synapse-workspace-01"
    },
    {
      "id": "CONTAINERAPP001",
      "type": "microsoft.app/containerapps",
      "name": "container-app-01"
    },
    {
      "id": "MANAGEDENV001",
      "type": "microsoft.app/managedenvironments",
      "name": "managed-env-01"
    }
  ]
}
EOF
    
    echo "Generated diverse inventory: $output_file"
}

# ==============================================================================
# Generate ARG-compatible diverse inventory (normalized .data schema)
# ==============================================================================
generate_diverse_inventory_arg() {
    local output_file="$1"
    local tmp_json
    tmp_json="${OUTPUT_DIR}/_tmp_diverse.json"
    generate_diverse_inventory "$tmp_json"
    jq -c '{
      data: (.resources | map({
        id: (.id // .name // "id"),
        name: (.name // "resource"),
        type: ( .type | sub("^microsoft"; "Microsoft") ),
        location: (.location // (.region // .metadata.source_region // "centralus")),
        subscriptionId: ("00000000-0000-0000-0000-000000000000"),
        resourceGroup: ("TestRG"),
        sku: ( .sku // .diskSku // "" ),
        vmSize: (.vmSize // ""),
        diskSku: (.diskSku // ""),
        diskSizeGB: (.diskSizeGB // null),
        storageAccountKind: (.storageAccountKind // ""),
        tier: (.tier // ""),
        capacity: (.capacity // ""),
        properties: {}
      }))
    }' "$tmp_json" > "$output_file"
    rm -f "$tmp_json"
    echo "Generated ARG-compatible diverse inventory: $output_file"
}

# ==============================================================================
# Generate compute-only inventory for focused testing
# ==============================================================================
generate_compute_inventory() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
{
  "metadata": {
    "source_region": "eastus",
    "generated_at": "2024-01-20",
    "description": "Compute-focused inventory for VM and disk testing"
  },
  "resources": [
    {
      "id": "VM001",
      "type": "microsoft.compute/virtualmachines",
      "vmSize": "Standard_B1s"
    },
    {
      "id": "VM002",
      "type": "microsoft.compute/virtualmachines",
      "vmSize": "Standard_B2s"
    },
    {
      "id": "VM003",
      "type": "microsoft.compute/virtualmachines",
      "vmSize": "Standard_D2s_v3"
    },
    {
      "id": "DISK001",
      "type": "microsoft.compute/disks",
      "diskSku": "Standard_LRS"
    },
    {
      "id": "DISK002",
      "type": "microsoft.compute/disks",
      "diskSku": "Premium_LRS"
    },
    {
      "id": "DISK003",
      "type": "microsoft.compute/disks",
      "diskSku": "StandardSSD_LRS"
    }
  ]
}
EOF
    
    echo "Generated compute inventory: $output_file"
}

# ==============================================================================
# Generate database inventory for testing DB SKUs
# ==============================================================================
generate_database_inventory() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
{
  "metadata": {
    "source_region": "westeurope",
    "generated_at": "2024-01-20",
    "description": "Database services inventory"
  },
  "resources": [
    {
      "id": "POSTGRES001",
      "type": "microsoft.dbforpostgresql/flexibleservers",
      "sku": "Standard_B1ms"
    },
    {
      "id": "POSTGRES002",
      "type": "microsoft.dbforpostgresql/flexibleservers",
      "sku": "Standard_B2s"
    },
    {
      "id": "POSTGRES003",
      "type": "microsoft.dbforpostgresql/flexibleservers",
      "sku": "Standard_D4s_v3"
    },
    {
      "id": "MYSQL001",
      "type": "microsoft.dbformysql/flexibleservers",
      "sku": "Standard_B1ms"
    },
    {
      "id": "MYSQL002",
      "type": "microsoft.dbformysql/flexibleservers",
      "sku": "Standard_D2s_v3"
    },
    {
      "id": "MARIADB001",
      "type": "microsoft.dbformariadb/servers",
      "sku": "B_Gen5_1"
    },
    {
      "id": "MARIADB002",
      "type": "microsoft.dbformariadb/servers",
      "sku": "GP_Gen5_4"
    }
  ]
}
EOF
    
    echo "Generated database inventory: $output_file"
}

# ==============================================================================
# Generate cache/container inventory
# ==============================================================================
generate_cache_inventory() {
    local output_file="$1"
    
    cat > "$output_file" << 'EOF'
{
  "metadata": {
    "source_region": "northeurope",
    "generated_at": "2024-01-20",
    "description": "Cache and container services inventory"
  },
  "resources": [
    {
      "id": "REDIS001",
      "type": "microsoft.cache/redis",
      "sku": "Basic",
      "size": "c0"
    },
    {
      "id": "REDIS002",
      "type": "microsoft.cache/redis",
      "sku": "Standard",
      "size": "c1"
    },
    {
      "id": "REDIS003",
      "type": "microsoft.cache/redis",
      "sku": "Premium",
      "size": "p1"
    },
    {
      "id": "AKS001",
      "type": "microsoft.containerservice/managedclusters",
      "vmSize": "Standard_D2s_v3"
    },
    {
      "id": "AKS002",
      "type": "microsoft.containerservice/managedclusters",
      "vmSize": "Standard_B2ms"
    },
    {
      "id": "REGISTRY001",
      "type": "microsoft.containerregistry/registries",
      "sku": "Basic"
    },
    {
      "id": "REGISTRY002",
      "type": "microsoft.containerregistry/registries",
      "sku": "Premium"
    }
  ]
}
EOF
    
    echo "Generated cache inventory: $output_file"
}

# ==============================================================================
# Main execution
# ==============================================================================
main() {
    echo "=== Test Inventory Generator ==="
    echo ""
    
    generate_diverse_inventory "${OUTPUT_DIR}/inventory_diverse.json"
    generate_diverse_inventory_arg "${OUTPUT_DIR}/inventory_diverse_arg.json"
    generate_compute_inventory "${OUTPUT_DIR}/inventory_compute.json"
    generate_database_inventory "${OUTPUT_DIR}/inventory_databases.json"
    generate_cache_inventory "${OUTPUT_DIR}/inventory_cache.json"
    
    echo ""
    echo "Generated test inventories in: $OUTPUT_DIR"
    ls -lh "${OUTPUT_DIR}"/inventory_*.json
}

main "$@"
