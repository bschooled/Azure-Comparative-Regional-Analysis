#!/usr/bin/env bash
# ==============================================================================
# Example 2: Management group scope
# ==============================================================================

../inv.sh \
  --mg Contoso-Prod \
  --source-region eastus2 \
  --target-region uksouth \
  --parallel 8
