#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"

action="${1:-}"
shift || true

case "$action" in
  detect)
    deploy_frontend_detect "$@"
    ;;
  scripts)
    deploy_frontend_scripts "$@"
    ;;
  install)
    deploy_frontend_install "$@"
    ;;
  build)
    deploy_frontend_build "$@"
    ;;
  ""|--help|-h|help)
    cat <<'EOF'
USAGE
  platform deploy frontend <command> <site|path>

COMMANDS
  detect    Detect Laravel/Node/Vite/package manager/scripts.
  scripts   List package.json scripts.
  install   Install frontend dependencies using lockfile-aware package manager.
  build     Run production `build` script and verify Vite manifest when applicable.
EOF
    ;;
  *)
    die "Frontend action không hợp lệ: $action"
    ;;
esac
