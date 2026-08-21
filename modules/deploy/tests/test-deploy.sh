#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/deploy/lib/deploy.sh"
R="$ROOT/modules/deploy/lib/runtime-health.sh"

for fn in \
  deploy_resolve_path deploy_compose deploy_prepare deploy_migrate \
  deploy_optimize deploy_health deploy_status \
  deploy_frontend_detect deploy_frontend_scripts \
  deploy_frontend_install deploy_frontend_build \
  deploy_frontend_package_manager deploy_frontend_run_owner
do
  grep -q "^${fn}()" "$F" || { echo "[ERROR] Missing $fn"; exit 1; }
done

for fn in \
  deploy_runtime_service_exists deploy_wait_service_ready_path \
  deploy_restart_php_runtime_path deploy_resolve_http_port_path \
  deploy_verify_application_http_path deploy_optimize_path deploy_health_path
do
  grep -q "^${fn}()" "$R" || { echo "[ERROR] Missing runtime guard $fn"; exit 1; }
done

# Contract: config cache refresh must be followed by PHP runtime restart.
grep -q 'Restart PHP runtime after cache refresh' "$R" || exit 1
grep -q 'deploy_restart_php_runtime_path' "$R" || exit 1

# Contract: Laravel must really boot; php-fpm -t / artisan --version alone is insufficient.
grep -q 'php artisan about --no-ansi' "$R" || exit 1

# Contract: deploy success requires a real local 2xx/3xx HTTP response.
grep -q "\^\[23\]\[0-9\]\[0-9\]\$" "$R" || exit 1
grep -q 'Application HTTP verification failed' "$R" || exit 1

# Runtime guard must be active for run/health/optimize entry points.
for cmd in run health optimize; do
  grep -q 'modules/deploy/lib/runtime-health.sh' "$ROOT/modules/deploy/commands/$cmd.sh" || exit 1
done

[[ -x "$ROOT/modules/deploy/commands/frontend.sh" ]] || exit 1
bash -n "$F"
bash -n "$R"
bash -n "$ROOT/modules/deploy/commands/run.sh"
bash -n "$ROOT/modules/deploy/commands/health.sh"
bash -n "$ROOT/modules/deploy/commands/optimize.sh"
bash -n "$ROOT/modules/deploy/commands/frontend.sh"
echo "[OK] Deploy Module v1.2 runtime restart + application HTTP gate"
