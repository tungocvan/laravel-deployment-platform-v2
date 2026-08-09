#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/core/lib/package.sh"
source "$PLATFORM_HOME/modules/package/lib/package.sh"
source "$PLATFORM_HOME/modules/package/lib/upgrade-audit.sh"

package_upgrade "$@"
