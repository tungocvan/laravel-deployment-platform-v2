#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"

deploy_rollback "$@"
