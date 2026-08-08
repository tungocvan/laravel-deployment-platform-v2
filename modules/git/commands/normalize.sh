#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"

platform_git_normalize_safe_directories
success "Git safe.directory đã normalize."
