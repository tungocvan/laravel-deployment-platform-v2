#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/backup/lib/backup.sh"
source "$PLATFORM_HOME/modules/site/lib/site.sh"
source "$PLATFORM_HOME/modules/site/lib/runtime.sh"
# Loaded after deploy.sh/runtime.sh intentionally: this overrides only the
# database wait used by Production Site Update without rewriting shared deploy
# helpers before the behavior is validated on a real managed site.
source "$PLATFORM_HOME/modules/site/lib/deploy-readiness.sh"
source "$PLATFORM_HOME/modules/site/lib/operations.sh"
source "$PLATFORM_HOME/modules/site/lib/reconcile.sh"

reconcile=0
for arg in "$@"; do
  [[ "$arg" == "--reconcile" ]] && reconcile=1
done

if [[ "$reconcile" -eq 1 ]]; then
  site_ops_reconcile "$@"
else
  site_ops_update "$@"
fi
