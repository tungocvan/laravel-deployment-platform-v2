#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
[[ -n "${1:-}" ]] || die "USAGE: platform git branch <path>"
platform_git_branch "${1:-}"
