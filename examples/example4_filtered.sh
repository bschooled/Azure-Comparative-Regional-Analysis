#!/usr/bin/env bash
# ==============================================================================
# Example 4: With resource type filtering
# ==============================================================================

../scripts/root/inv.sh \
  --all \
  --source-region eastus \
  --target-region westeurope \
  --resource-types "Microsoft.Compute/virtualMachines,Microsoft.Storage/storageAccounts,Microsoft.Compute/disks" \
  --parallel 16
