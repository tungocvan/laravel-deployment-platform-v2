#!/usr/bin/env bash
set -Eeuo pipefail

PLATFORM_HOME="${PLATFORM_HOME:-/opt/laravel-deployment-platform}"
VERSION_FILE="$PLATFORM_HOME/VERSION"
INVENTORY_FILE="${INVENTORY_FILE:-$PLATFORM_HOME/state/sites.json}"

source "$PLATFORM_HOME/core/lib/common.sh"
source "$PLATFORM_HOME/core/lib/module.sh"
source "$PLATFORM_HOME/core/lib/config.sh"
source "$PLATFORM_HOME/core/dispatcher.sh"
