#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/site/lib/site.sh"
source "$PLATFORM_HOME/modules/ui/lib/ui.sh"
source "$PLATFORM_HOME/modules/ui/menus/sites.sh"
source "$PLATFORM_HOME/modules/ui/menus/backup.sh"
source "$PLATFORM_HOME/modules/ui/menus/deploy.sh"
source "$PLATFORM_HOME/modules/ui/menus/doctor.sh"
source "$PLATFORM_HOME/modules/ui/menus/infrastructure.sh"
source "$PLATFORM_HOME/modules/ui/menus/packages.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE
  platform-v2
  platform-v2 menu
  platform-v2 ui

Simple interactive frontend over existing Platform commands.
EOF
  exit 0
fi

ui_main
