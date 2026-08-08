#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
[[ -n "${1:-}" ]] || die "USAGE: platform git trust <path>"
platform_git_trust "${1:-}"
success "Git safe.directory OK: ${1:-}"
