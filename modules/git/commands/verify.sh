#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
[[ -n "${1:-}" ]] || die "USAGE: platform git verify <path>"
platform_git_verify "${1:-}"
success "Git repository hợp lệ: ${1:-}"
