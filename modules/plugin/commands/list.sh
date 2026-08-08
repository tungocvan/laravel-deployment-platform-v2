#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/plugin/lib/plugin.sh"

plugin_list "$@"
