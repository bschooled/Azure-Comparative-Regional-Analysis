#!/usr/bin/env bash
# ==============================================================================
# Example 1: Tenant-wide scope (all subscriptions)
# ==============================================================================

../scripts/root/inv.sh \
  --all \
  --source-region eastus \
  --target-region westeurope \
  --parallel 12 \
  --cache-dir ../.cache
