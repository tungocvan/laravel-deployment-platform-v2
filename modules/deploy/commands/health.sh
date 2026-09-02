#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/deploy/lib/runtime-health.sh"

if [[ "${2:-}" == "--storage-only" ]]; then
  deploy_storage_repair "${1:-}"
  exit 0
fi

[[ $# -le 1 ]] || die "Option không hợp lệ: ${2:-}"
deploy_health "$@"
