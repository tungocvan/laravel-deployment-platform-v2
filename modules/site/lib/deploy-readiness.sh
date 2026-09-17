#!/usr/bin/env bash

# Production Site Operations V2 readiness override.
#
# The legacy deploy_wait_database() assumes DB_* are exported as container
# process environment variables. Managed Laravel sites may instead load those
# values from the application .env, so getenv() can be empty even while the
# application has a valid database connection.
#
# This override is deliberately scoped to Site Operations V2. It leaves the
# shared deploy.sh intact and can be promoted there separately after production
# validation.

site_ops_laravel_database_ready() {
  local project_dir="$1" app="${2:-app}"

  deploy_compose "$project_dir" exec -T "$app" php -r '
    require "vendor/autoload.php";
    $app = require "bootstrap/app.php";
    $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
    try {
        Illuminate\Support\Facades\DB::connection()->getPdo();
        exit(0);
    } catch (Throwable $e) {
        exit(1);
    }
  ' >/dev/null 2>&1
}

# Overrides deploy_wait_database() only after modules/deploy/lib/deploy.sh has
# been sourced by the Site Update command.
deploy_wait_database() {
  local project_dir="$1" timeout="${2:-120}"
  local started now app announced_container=0 announced_probe=0

  app="$(site_runtime_app_service "$project_dir" 2>/dev/null || true)"
  [[ -n "$app" ]] || app="app"
  started="$(date +%s)"

  while true; do
    if deploy_compose "$project_dir" ps db 2>/dev/null | grep -Eqi 'Up|healthy|running'; then
      if [[ "$announced_container" -eq 0 ]]; then
        echo "[WAIT] Database container is running/healthy."
        announced_container=1
      fi

      if [[ "$announced_probe" -eq 0 ]]; then
        echo "[WAIT] Checking Laravel database connection via resolved application config..."
        announced_probe=1
      fi

      if site_ops_laravel_database_ready "$project_dir" "$app"; then
        echo "[OK] Laravel database connection ready."
        return 0
      fi
    fi

    now="$(date +%s)"
    if (( now - started >= timeout )); then
      echo "[ERROR] Laravel database readiness failed after ${timeout}s."
      echo "        Docker DB may be healthy, but Laravel could not open its configured connection."
      return 1
    fi

    sleep 2
  done
}
