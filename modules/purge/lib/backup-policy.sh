#!/usr/bin/env bash

# Purge-only backup policy:
# - DB service/container absent or stopped => skip database backup.
# - DB container running but configured database absent => skip database backup.
# - DB exists => database backup remains mandatory; any dump failure aborts purge.
# This file is sourced only by the site purge command, after backup.sh.

# Preserve the normal backup implementation before wrapping it for purge.
eval "$(declare -f backup_create | sed '1s/^backup_create[[:space:]]*()/backup_create_standard()/')"

site_purge_database_backup_state() {
  local site="$1" project="$2"
  local database cid running probe rc

  database="$(inventory_get_field "$site" database 2>/dev/null || true)"
  if [[ -z "$database" ]]; then
    echo "skip:no-database-config"
    return 0
  fi

  # Purge must not start a stopped DB merely to create a backup.
  cid="$(deploy_compose "$project" ps -q db 2>/dev/null | head -n1 || true)"
  if [[ -z "$cid" ]]; then
    echo "skip:container-not-running"
    return 0
  fi

  running="$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || true)"
  if [[ "$running" != "true" ]]; then
    echo "skip:container-not-running"
    return 0
  fi

  # Probe the configured DB using root credentials already present inside the
  # MariaDB/MySQL container. Exit 10 means the database truly does not exist.
  # Any other probe failure is treated as unknown/error, never as "absent".
  set +e
  probe="$(docker exec -e PLATFORM_PURGE_DATABASE="$database" "$cid" sh -lc '
    client="$(command -v mariadb || command -v mysql || true)"
    [ -n "$client" ] || exit 20
    rootpw="${MARIADB_ROOT_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
    [ -n "$rootpw" ] || exit 21
    err="$(mktemp)"
    MYSQL_PWD="$rootpw" "$client" -uroot "$PLATFORM_PURGE_DATABASE" -Nse "SELECT 1" >/dev/null 2>"$err"
    rc=$?
    if [ "$rc" -eq 0 ]; then rm -f "$err"; exit 0; fi
    if grep -qi "Unknown database" "$err"; then rm -f "$err"; exit 10; fi
    cat "$err" >&2
    rm -f "$err"
    exit 22
  ' 2>&1)"
  rc=$?
  set -e

  case "$rc" in
    0)
      echo "backup"
      return 0
      ;;
    10)
      echo "skip:database-not-found"
      return 0
      ;;
    *)
      echo "error:${probe:-database probe failed}"
      return 0
      ;;
  esac
}

backup_create() {
  local site="${1:-}"
  [[ -n "$site" ]] || die "USAGE: platform backup create <site>"

  local project state reason
  project="$(backup_resolve_site_path "$site")"
  state="$(site_purge_database_backup_state "$site" "$project")"

  case "$state" in
    backup)
      echo "[INFO] Database tồn tại và container đang chạy; database backup là bắt buộc."
      backup_create_standard "$@"
      ;;
    skip:container-not-running)
      warn "Không tìm thấy container database đang chạy. Bỏ qua database backup cho PURGE."
      backup_create_standard "$@" --no-database
      ;;
    skip:database-not-found)
      reason="$(inventory_get_field "$site" database 2>/dev/null || true)"
      warn "Database '${reason:-unknown}' không tồn tại. Bỏ qua database backup cho PURGE."
      backup_create_standard "$@" --no-database
      ;;
    skip:no-database-config)
      warn "Site không có database được khai báo. Bỏ qua database backup cho PURGE."
      backup_create_standard "$@" --no-database
      ;;
    error:*)
      platform_die "$PLATFORM_EXIT_OPERATION" "PURGE.DB_PROBE_FAILED" \
        "Không thể xác định an toàn database có tồn tại hay không: ${state#error:}. Purge bị dừng."
      ;;
    *)
      platform_die "$PLATFORM_EXIT_OPERATION" "PURGE.DB_PROBE_FAILED" \
        "Trạng thái kiểm tra database không hợp lệ: $state"
      ;;
  esac
}
