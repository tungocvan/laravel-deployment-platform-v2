#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
[[ -n "${1:-}" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.ARGUMENT_REQUIRED" "USAGE: platform git verify <path>"
[[ -e "${1:-}" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.PATH_NOT_FOUND" "Git path không tồn tại: ${1:-}"
[[ -d "${1:-}/.git" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.NOT_REPOSITORY" "Không phải Git working tree: ${1:-}"
platform_git_verify "${1:-}"
success "Git repository hợp lệ: ${1:-}"
