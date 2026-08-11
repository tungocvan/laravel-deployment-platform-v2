#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/site/lib/create-strategy.sh"
source "$PLATFORM_HOME/modules/site/lib/storage.sh"
site_storage_command "$@"
