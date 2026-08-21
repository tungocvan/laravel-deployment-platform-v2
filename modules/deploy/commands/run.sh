#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
# Keep deploy run on the same Docker-health readiness gate used by Create Site.
# Source after deploy.sh so deploy_wait_database() is intentionally overridden.
source "$PLATFORM_HOME/modules/deploy/lib/readiness.sh"
# Strengthen deploy completion: restart long-lived PHP runtime after cache refresh
# and require a real local HTTP 2xx/3xx response before reporting success.
source "$PLATFORM_HOME/modules/deploy/lib/runtime-health.sh"
deploy_run "$@"
