#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/site/lib/site.sh"
source "$PLATFORM_HOME/modules/site/lib/repository.sh"
export PLATFORM_DEFAULT_SITE_REPO="${PLATFORM_DEFAULT_SITE_REPO:-$(site_canonical_repo)}"
source "$PLATFORM_HOME/modules/ui/lib/ui.sh"
source "$PLATFORM_HOME/modules/ui/flows/repository-access.sh"
source "$PLATFORM_HOME/modules/ui/menus/sites.sh"
source "$PLATFORM_HOME/modules/ui/flows/bootstrap-repository.sh"
source "$PLATFORM_HOME/modules/ui/menus/backup.sh"
source "$PLATFORM_HOME/modules/ui/menus/deploy.sh"
source "$PLATFORM_HOME/modules/ui/menus/doctor.sh"
source "$PLATFORM_HOME/modules/ui/menus/infrastructure.sh"
source "$PLATFORM_HOME/modules/ui/menus/packages.sh"
# Loaded last on purpose: this overrides the legacy terse ui_main() from ui.sh
# with the descriptive Platform 2.1 operations console + quick guide.
source "$PLATFORM_HOME/modules/ui/menus/main.sh"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'EOF'
USAGE
  platform-v2
  platform-v2 menu
  platform-v2 ui

Interactive operations console over existing Platform commands.
Menu labels describe the contained operations and include an in-console quick guide.
EOF
  exit 0
fi

ui_main
