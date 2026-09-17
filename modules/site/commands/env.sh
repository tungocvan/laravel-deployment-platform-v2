#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/site/lib/site.sh"
source "$PLATFORM_HOME/modules/site/lib/provision.sh"
source "$PLATFORM_HOME/modules/site/lib/runtime.sh"
source "$PLATFORM_HOME/modules/site/lib/operations.sh"
source "$PLATFORM_HOME/modules/site/lib/env-management.sh"

site="${1:-}"
action="${2:-}"
case "$action" in
  --keys) site_ops_env_list_keys "$site" ;;
  --edit) site_ops_env_edit "$site" ;;
  *) site_ops_env_apply "$@" ;;
esac
