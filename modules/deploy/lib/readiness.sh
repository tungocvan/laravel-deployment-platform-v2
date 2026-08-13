#!/usr/bin/env bash
#
# Database readiness override.
#
# IMPORTANT: Laravel managed sites mount .env into the app container; DB_* is
# not guaranteed to exist in the container process environment. Do not probe
# readiness with getenv(DB_*). Bootstrap Laravel so Dotenv/config are loaded,
# then ask the configured database connection for a PDO handle.
#

deploy_wait_database() {
  local project_dir="$1" timeout="${2:-120}"
  local started now last_diag=""
  started="$(date +%s)"

  while true; do
    if deploy_compose "$project_dir" ps db 2>/dev/null | grep -Eq 'Up|healthy|running'; then
      if deploy_compose "$project_dir" exec -T app php -r '
        try {
          require "vendor/autoload.php";
          $app = require "bootstrap/app.php";
          $app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
          $app->make("db")->connection()->getPdo();
          exit(0);
        } catch (Throwable $e) {
          fwrite(STDERR, get_class($e).": ".$e->getMessage().PHP_EOL);
          exit(1);
        }
      ' >/dev/null 2>"/tmp/platform-db-readiness-$$.err"; then
        rm -f "/tmp/platform-db-readiness-$$.err"
        echo "[OK] Database connection ready"
        return 0
      else
        last_diag="$(tail -n 1 "/tmp/platform-db-readiness-$$.err" 2>/dev/null || true)"
      fi
    fi

    now="$(date +%s)"
    if (( now - started >= timeout )); then
      rm -f "/tmp/platform-db-readiness-$$.err"
      [[ -n "$last_diag" ]] && echo "[ERROR] Database readiness detail: $last_diag" >&2
      die "Timeout chờ database (${timeout}s)."
    fi
    sleep 2
  done
}
