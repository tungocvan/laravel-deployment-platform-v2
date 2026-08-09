#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"

[[ -n "${1:-}" ]] || platform_die \
  "$PLATFORM_EXIT_USAGE" \
  "INVENTORY.ARGUMENT_REQUIRED" \
  "USAGE: platform inventory show <name|domain|path>"

inventory_show "$@"
