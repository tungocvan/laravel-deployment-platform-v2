#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/nginx/lib/nginx.sh"
source "$PLATFORM_HOME/modules/ssl/lib/ssl.sh"
platform_ssl_list "$@"
