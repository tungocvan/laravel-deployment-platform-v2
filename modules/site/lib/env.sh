#!/usr/bin/env bash

site_env_context() {
  local key="$1"
  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"

  SITE_ENV_NAME="$(inventory_get_field "$key" name)"
  SITE_ENV_PATH="$(inventory_get_field "$key" path)"
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
  stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  target="$backup_dir/.env.$stamp"
  mkdir -p "$backup_dir"
  chmod 700 "$SITE_ENV_PATH/.platform-backups" "$backup_dir" 2>/dev/null || true
  cp -p "$SITE_ENV_PATH/.env" "$target"
  chmod 600 "$target"
  echo "$target"
}

site_env_write_value() {
  local file="$1" env_key="$2" env_value="$3"
  python3 - "$file" "$env_key" "$env_value" <<'PY'
import os,sys,tempfile
path,key,value=sys.argv[1:]
with open(path,encoding='utf-8') as f: lines=f.readlines()
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
    if out and not out[-1].endswith('\n'): out[-1]+='\n'
    out.append(replacement)
fd,tmp=tempfile.mkstemp(prefix='.env.',dir=os.path.dirname(path),text=True)
try:
    with os.fdopen(fd,'w',encoding='utf-8') as f:
        f.writelines(out)
        f.flush(); os.fsync(f.fileno())
    os.chmod(tmp,0o600)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

site_env_refresh() {
  local key="$1"
  require_root
  site_env_context "$key"

  echo "[ENV] Refresh runtime: $SITE_ENV_NAME"
  case "$SITE_ENV_STRATEGY" in
    repository)
      site_create_repository_compose "$SITE_ENV_PATH" "$SITE_ENV_COMPOSE" up -d --force-recreate app queue scheduler socket
      site_create_repository_compose "$SITE_ENV_PATH" "$SITE_ENV_COMPOSE" exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
      site_create_repository_compose "$SITE_ENV_PATH" "$SITE_ENV_COMPOSE" exec -T app php artisan config:cache
      ;;
    platform|"")
      deploy_compose "$SITE_ENV_PATH" up -d --force-recreate app queue scheduler socket
      deploy_compose "$SITE_ENV_PATH" exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
      deploy_compose "$SITE_ENV_PATH" exec -T app php artisan config:cache
      ;;
    *) die "Runtime strategy không hỗ trợ env refresh: $SITE_ENV_STRATEGY" ;;
  esac
  success "Environment runtime đã refresh: $SITE_ENV_NAME"
}

site_env_set() {
  local key="$1" env_key="$2" env_value="$3" refresh="${4:-1}"
  require_root
  site_env_validate_key "$env_key"
  site_env_context "$key"

  local backup
  backup="$(site_env_backup "$key")"
  site_env_write_value "$SITE_ENV_PATH/.env" "$env_key" "$env_value"
  echo "[ENV] Updated: $env_key"
  echo "[ENV] Backup : $backup"
  [[ "$refresh" -eq 0 ]] || site_env_refresh "$key"
}

site_env_command() {
  local key="${1:-}" action="${2:-}"; shift 2 || true
  [[ -n "$key" && -n "$action" ]] || die "USAGE: platform site env <site> <get|set|backup|refresh> ..."

  case "$action" in
    get)
      local env_key="${1:-}"
      [[ -n "$env_key" ]] || die "USAGE: platform site env <site> get <KEY>"
      site_env_get "$key" "$env_key"
      ;;
    set)
      local env_key="${1:-}" env_value="${2:-}" refresh=1 arg
      [[ -n "$env_key" && "$#" -ge 2 ]] || die "USAGE: platform site env <site> set <KEY> <VALUE> [--no-refresh]"
      shift 2 || true
      for arg in "$@"; do
        case "$arg" in
          --no-refresh) refresh=0 ;;
          *) die "Option không hợp lệ: $arg" ;;
        esac
      done
      site_env_set "$key" "$env_key" "$env_value" "$refresh"
      ;;
    backup) site_env_backup "$key" ;;
    refresh) site_env_refresh "$key" ;;
    *) die "Env action không hợp lệ: $action" ;;
  esac
}
