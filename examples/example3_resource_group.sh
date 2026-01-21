#!/usr/bin/env bash
# ==============================================================================
# Example 3: Resource group scope
# ==============================================================================

# Replace with your subscription ID and resource group name
SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000000"
RESOURCE_GROUP="WorkloadRG"

../inv.sh \
  --rg "${SUBSCRIPTION_ID}:${RESOURCE_GROUP}" \
  --source-region westus3 \
  --target-region centralus
