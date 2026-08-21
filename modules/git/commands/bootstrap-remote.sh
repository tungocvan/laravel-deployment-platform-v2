#!/usr/bin/env bash
set -Eeuo pipefail
exec bash "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/modules/git/lib/bootstrap-remote.sh" "$@"
