#!/usr/bin/env bash
#
# Database readiness override.
#
# Wait-database is a Docker/MariaDB readiness gate, not an application config
# validation step. The db service already receives MARIADB_DATABASE and
# MARIADB_ROOT_PASSWORD from Compose, so probe MariaDB from inside that
# container. Do not depend on DB_* being exported in the app process.
# Application/Laravel DB configuration is validated later by migrate/health.
#

deploy_wait_database() {
  local project_dir="$1" timeout="${2:-120}"
  local started now last_diag=""
  started="$(date +%s)"

  while true; do
    if deploy_compose "$project_dir" ps db 2>/dev/null | grep -Eqi 'Up|healthy|running'; then
      if deploy_compose "$project_dir" exec -T db sh -lc '
        set -eu
        command -v mariadb >/dev/null 2>&1 || { echo "mariadb client missing in db container" >&2; exit 2; }
        mariadb -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD" -Nse "SELECT 1" >/dev/null
        mariadb -h 127.0.0.1 -uroot -p"$MARIADB_ROOT_PASSWORD" -Nse \
          "SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME=\"$MARIADB_DATABASE\"" \
          | grep -Fxq "$MARIADB_DATABASE"
      ' >/dev/null 2>"/tmp/platform-db-readiness-$$.err"; then
        rm -f "/tmp/platform-db-readiness-$$.err"
        echo "[OK] Database service ready"
        return 0
      else
        last_diag="$(tail -n 1 "/tmp/platform-db-readiness-$$.err" 2>/dev/null || true)"
      fi
    else
      last_diag="db service not running/healthy yet"
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
