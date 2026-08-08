#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/deploy/lib/deploy.sh"

for fn in \
  deploy_resolve_path deploy_compose deploy_prepare deploy_migrate \
  deploy_optimize deploy_health deploy_status \
  deploy_frontend_detect deploy_frontend_scripts \
  deploy_frontend_install deploy_frontend_build \
  deploy_frontend_package_manager deploy_frontend_run_owner
do
  grep -q "^${fn}()" "$F" || { echo "[ERROR] Missing $fn"; exit 1; }
done

[[ -x "$ROOT/modules/deploy/commands/frontend.sh" ]] || exit 1
bash -n "$F"
bash -n "$ROOT/modules/deploy/commands/frontend.sh"
echo "[OK] Deploy Module v1.1 frontend API"
