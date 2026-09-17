#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/site/lib/runtime.sh"
site="${1:-}"; [[ -n "$site" ]] || die "USAGE: platform site runtime <site>"
site_runtime_status "$site"
