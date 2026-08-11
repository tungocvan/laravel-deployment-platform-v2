#!/usr/bin/env bash

site_env_context() {
  local key="$1"
  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"

  SITE_ENV_NAME="$(inventory_get_field "$key" name)"
  SITE_ENV_PATH="$(inventory_get_field "$key" path)"
  SITE_ENV_DOMAIN="$(inventory_get_field "$key" domain 2>/dev/null || true)"
  SITE_ENV_STRATEGY="$(inventory_get_field "$key" runtime_strategy 2>/dev/null || true)"
  SITE_ENV_STRATEGY="${SITE_ENV_STRATEGY:-platform}"
  SITE_ENV_COMPOSE="$(inventory_get_field "$key" compose_file 2>/dev/null || true)"
  SITE_ENV_COMPOSE="${SITE_ENV_COMPOSE:-compose.yaml}"

  [[ -d "$SITE_ENV_PATH" ]] || die "Project path không tồn tại: $SITE_ENV_PATH"
  [[ -f "$SITE_ENV_PATH/.env" ]] || die "Site chưa có .env: $SITE_ENV_PATH/.env"
}

site_env_validate_key() {
  [[ "${1:-}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "Tên biến .env không hợp lệ: ${1:-}"
}

site_env_apply_permissions() {
  local file="$1"
  [[ -f "$file" ]] || die "ENV file không tồn tại: $file"
  chown root:www-data "$file"
  chmod 660 "$file"
}

site_env_compose() {
  case "$SITE_ENV_STRATEGY" in
    repository)
      site_create_repository_compose "$SITE_ENV_PATH" "$SITE_ENV_COMPOSE" "$@"
      ;;
    platform|"")
      deploy_compose "$SITE_ENV_PATH" "$@"
      ;;
    *) die "Runtime strategy không hỗ trợ env operation: $SITE_ENV_STRATEGY" ;;
  esac
}

site_env_status() {
  local key="$1"
  require_root
  site_env_context "$key"

  echo "Site       : $SITE_ENV_NAME"
  echo "Path       : $SITE_ENV_PATH"
  echo "Domain     : ${SITE_ENV_DOMAIN:-N/A}"
  echo "Strategy   : $SITE_ENV_STRATEGY"
  echo "===== .ENV ====="
  stat -c 'OWNER=%U GROUP=%G MODE=%a INODE=%i SIZE=%s FILE=%n' "$SITE_ENV_PATH/.env"
  echo "===== APP ACCESS AS WWW-DATA ====="
  site_env_compose exec -T --user www-data app php -r '
$p="/var/www/html/.env";
echo "exists=".(file_exists($p)?"true":"false").PHP_EOL;
echo "readable=".(is_readable($p)?"true":"false").PHP_EOL;
echo "writable=".(is_writable($p)?"true":"false").PHP_EOL;
'
}

site_env_get() {
  local key="$1" env_key="$2"
  require_root
  site_env_validate_key "$env_key"
  site_env_context "$key"

  python3 - "$SITE_ENV_PATH/.env" "$env_key" <<'PY'
import sys
path,key=sys.argv[1:]
found=False
with open(path,encoding='utf-8') as f:
    for raw in f:
        line=raw.rstrip('\n')
        if line.startswith(key+'='):
            print(line[len(key)+1:])
            found=True
            break
raise SystemExit(0 if found else 4)
PY
}

site_env_backup() {
  local key="$1"
  require_root
  site_env_context "$key"

  local backup_dir="$SITE_ENV_PATH/.platform-backups/env" stamp target
  stamp="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  target="$backup_dir/.env.$stamp"
  mkdir -p "$backup_dir"
  chmod 700 "$SITE_ENV_PATH/.platform-backups" "$backup_dir" 2>/dev/null || true
  cp -p "$SITE_ENV_PATH/.env" "$target"
  chown root:root "$target"
  chmod 600 "$target"
  echo "$target"
}

site_env_latest_backup() {
  local backup_dir="$SITE_ENV_PATH/.platform-backups/env"
  [[ -d "$backup_dir" ]] || return 1
  find "$backup_dir" -maxdepth 1 -type f -name '.env.*' -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr \
    | head -n 1 \
    | cut -d' ' -f2-
}

# Preserve the existing .env inode. Repository sites bind-mount ./.env as a
# single Docker file; rename/replace would leave running containers attached to
# the old inode. All writes therefore lock and rewrite the existing inode.
site_env_write_content_in_place() {
  local target="$1" source="$2"
  python3 - "$target" "$source" <<'PY'
import fcntl, os, sys
path,source=sys.argv[1:]
with open(source,'rb') as src:
    data=src.read()
with open(path,'r+b',buffering=0) as dst:
    fcntl.flock(dst.fileno(), fcntl.LOCK_EX)
    try:
        dst.seek(0)
        dst.write(data)
        dst.truncate()
        dst.flush()
        os.fsync(dst.fileno())
    finally:
        fcntl.flock(dst.fileno(), fcntl.LOCK_UN)
PY
}

site_env_write_value() {
  local file="$1" env_key="$2" env_value="$3"
  python3 - "$file" "$env_key" "$env_value" <<'PY'
import fcntl, os, sys
path,key,value=sys.argv[1:]
with open(path,'r+',encoding='utf-8',newline='') as f:
    fcntl.flock(f.fileno(), fcntl.LOCK_EX)
    try:
        f.seek(0)
        lines=f.readlines()
        replacement=f'{key}={value}\n'
        out=[]
        replaced=False
        for line in lines:
            if line.startswith(key+'='):
                if not replaced:
                    out.append(replacement)
                    replaced=True
                continue
            out.append(line)
        if not replaced:
            if out and not out[-1].endswith('\n'):
                out[-1]+='\n'
            out.append(replacement)
        f.seek(0)
        f.writelines(out)
        f.truncate()
        f.flush()
        os.fsync(f.fileno())
    finally:
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)
PY
}

site_env_validate() {
  local key="$1"
  require_root
  site_env_context "$key"

  local env_file="$SITE_ENV_PATH/.env"
  echo "[ENV] Validate permissions"
  local owner group mode
  owner="$(stat -c '%U' "$env_file")"
  group="$(stat -c '%G' "$env_file")"
  mode="$(stat -c '%a' "$env_file")"
  [[ "$owner" == "root" && "$group" == "www-data" && "$mode" == "660" ]] \
    || die ".env permission không đúng; yêu cầu root:www-data 660, hiện tại $owner:$group $mode"

  echo "[ENV] Validate actual write as www-data"
  site_env_compose exec -T --user www-data app php -r '
$p="/var/www/html/.env";
if (!file_exists($p) || !is_readable($p) || !is_writable($p)) { exit(20); }
$data=file_get_contents($p);
if ($data === false) { exit(21); }
$written=@file_put_contents($p,$data,LOCK_EX);
if ($written === false || $written !== strlen($data)) { exit(22); }
'

  echo "[ENV] Validate Laravel boot"
  site_env_compose exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan about >/dev/null

  echo "[ENV] Validate web health"
  site_env_compose exec -T web wget -q -O /dev/null http://127.0.0.1:8080/up

  success "Environment validation PASS: $SITE_ENV_NAME"
}

site_env_refresh() {
  local key="$1"
  require_root
  site_env_context "$key"

  echo "[ENV] Refresh Laravel cache only: $SITE_ENV_NAME"
  site_env_apply_permissions "$SITE_ENV_PATH/.env"
  site_env_compose exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
  site_env_validate "$key"
  success "Environment runtime đã refresh an toàn: $SITE_ENV_NAME"
}

site_env_restore_file() {
  local key="$1" backup="${2:-}"
  require_root
  site_env_context "$key"

  local backup_dir="$SITE_ENV_PATH/.platform-backups/env" resolved
  if [[ -z "$backup" || "$backup" == "latest" ]]; then
    backup="$(site_env_latest_backup || true)"
  fi
  [[ -n "$backup" && -f "$backup" ]] || die "Không tìm thấy ENV backup để restore."

  resolved="$(readlink -f "$backup")"
  [[ "$resolved" == "$(readlink -f "$backup_dir")"/* ]] || die "Chỉ được restore backup trong $backup_dir"

  echo "[ENV] Restore in-place: $resolved"
  site_env_write_content_in_place "$SITE_ENV_PATH/.env" "$resolved"
  site_env_apply_permissions "$SITE_ENV_PATH/.env"
  site_env_compose exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
  site_env_validate "$key"
  success "Environment restore hoàn tất: $SITE_ENV_NAME"
}

site_env_set() {
  local key="$1" env_key="$2" env_value="$3"
  require_root
  site_env_validate_key "$env_key"
  site_env_context "$key"

  local backup env_file="$SITE_ENV_PATH/.env" rc=0 inode_before inode_after
  backup="$(site_env_backup "$key")"
  inode_before="$(stat -c '%i' "$env_file")"

  echo "[ENV] Backup : $backup"
  echo "[ENV] Update : $env_key"
  site_env_write_value "$env_file" "$env_key" "$env_value"
  site_env_apply_permissions "$env_file"
  inode_after="$(stat -c '%i' "$env_file")"
  [[ "$inode_before" == "$inode_after" ]] || die "ENV inode đã thay đổi ngoài ý muốn ($inode_before -> $inode_after)."

  # ENV management never recreates/restarts Docker services. It preserves the
  # bind-mounted .env inode, clears Laravel caches and validates the live runtime.
  site_env_compose exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear || rc=$?
  if [[ "$rc" -eq 0 ]]; then
    site_env_validate "$key" || rc=$?
  fi

  if [[ "$rc" -ne 0 ]]; then
    warn "ENV update validation thất bại; rollback in-place từ backup: $backup"
    site_env_write_content_in_place "$env_file" "$backup"
    site_env_apply_permissions "$env_file"
    site_env_compose exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear >/dev/null 2>&1 || true
    if site_env_validate "$key" >/dev/null 2>&1; then
      warn "Rollback .env hoàn tất; runtime cũ đã được khôi phục."
    else
      warn "Rollback file đã thực hiện nhưng health-check vẫn fail; cần kiểm tra site doctor/logs."
    fi
    return "$rc"
  fi

  success "Environment key cập nhật an toàn: $SITE_ENV_NAME / $env_key"
}

site_env_command() {
  local key="${1:-}" action="${2:-}"; shift 2 || true
  [[ -n "$key" && -n "$action" ]] || die "USAGE: platform site env <site> <status|get|set|backup|restore|refresh|validate> ..."

  case "$action" in
    status) site_env_status "$key" ;;
    get)
      local env_key="${1:-}"
      [[ -n "$env_key" ]] || die "USAGE: platform site env <site> get <KEY>"
      site_env_get "$key" "$env_key"
      ;;
    set)
      local env_key="${1:-}" env_value="${2:-}"
      [[ -n "$env_key" && "$#" -ge 2 ]] || die "USAGE: platform site env <site> set <KEY> <VALUE>"
      site_env_set "$key" "$env_key" "$env_value"
      ;;
    backup) site_env_backup "$key" ;;
    restore) site_env_restore_file "$key" "${1:-latest}" ;;
    refresh) site_env_refresh "$key" ;;
    validate) site_env_validate "$key" ;;
    *) die "Env action không hợp lệ: $action" ;;
  esac
}
