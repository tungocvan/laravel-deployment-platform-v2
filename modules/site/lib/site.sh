#!/usr/bin/env bash

site_projects_root() { printf '%s' "${PROJECTS_ROOT:-/opt/projects}"; }

site_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

site_validate_domain() {
  [[ "$1" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]]
}

site_confirm() {
  local prompt="${1:-Tiếp tục?}" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

site_assert_name_available() {
  local name="$1"
  if inventory_find_json "$name" >/dev/null 2>&1; then
    die "Site name đã tồn tại trong Inventory: $name"
  fi
  return 0
}

site_assert_domain_available() {
  local domain="$1"
  if inventory_find_json "$domain" >/dev/null 2>&1; then
    die "Domain đã tồn tại trong Inventory: $domain"
  fi
  return 0
}

site_choose_port() {
  local requested="$1" start="$2"
  if [[ "$requested" == "auto" ]]; then
    inventory_find_free_port "$start"
    return
  fi
  [[ "$requested" =~ ^[0-9]+$ ]] || die "Port phải là số hoặc auto: $requested"
  if inventory_port_used "$requested"; then
    die "Port đang được sử dụng/reserved: $requested"
  fi
  echo "$requested"
}

site_step() { printf '[%02d/12] %s\n' "$1" "$2"; }

site_list() { inventory_list; }
site_show() { inventory_show "$@"; }

site_exec() {
  local site="${1:-}"
  [[ -n "$site" ]] || die "USAGE: platform site exec <site> <command...>"
  shift || true
  [[ "$#" -gt 0 ]] || die "Thiếu command."
  local path
  path="$(inventory_get_field "$site" path)"
  deploy_compose "$path" exec -T app "$@"
}

site_doctor() {
  local site="${1:-}"
  [[ -n "$site" ]] || die "USAGE: platform site doctor <site>"

  local path domain http_port socket_port errors=0
  path="$(inventory_get_field "$site" path)"
  domain="$(inventory_get_field "$site" domain)"
  http_port="$(inventory_get_field "$site" http_port)"
  socket_port="$(inventory_get_field "$site" socket_port)"

  [[ -d "$path" ]] && echo "[OK] Path: $path" || { echo "[ERROR] Path: $path"; errors=$((errors+1)); }
  [[ -f "$path/.env" ]] && echo "[OK] .env" || { echo "[ERROR] .env missing"; errors=$((errors+1)); }
  [[ -f "$path/.docker-platform.env" ]] && echo "[OK] .docker-platform.env" || { echo "[ERROR] .docker-platform.env missing"; errors=$((errors+1)); }

  if platform_git_verify "$path" >/dev/null 2>&1; then
    echo "[OK] Git repository"
    echo "[OK] Git readable"
  else
    echo "[ERROR] Git repository"
    errors=$((errors+1))
  fi

  if deploy_compose "$path" ps web >/dev/null 2>&1; then
    echo "[OK] Docker compose"
  else
    echo "[ERROR] Docker compose"
    errors=$((errors+1))
  fi

  [[ -n "$domain" ]] && echo "[OK] Domain: $domain" || { echo "[ERROR] Domain missing"; errors=$((errors+1)); }
  [[ -n "$http_port" ]] && echo "[OK] HTTP port: $http_port" || { echo "[ERROR] HTTP port missing"; errors=$((errors+1)); }
  [[ -n "$socket_port" ]] && echo "[OK] Socket port: $socket_port" || echo "[WARN] Socket port missing"

  [[ "$errors" -eq 0 ]] || die "Site doctor phát hiện $errors lỗi."
  success "Site doctor OK: $site"
}

site_duplicate_report() {
  python3 - "$@" <<'PY'
import json,sys
source,name,domain,http,socket,database=sys.argv[1:]
print(json.dumps({
  "status":"success",
  "strategy":"duplicate-live",
  "source":source,
  "destination":name,
  "domain":domain,
  "http_port":int(http),
  "socket_port":int(socket),
  "database":database
},ensure_ascii=False,indent=2))
PY
}

site_duplicate() {
  require_root
  require_command rsync
  require_command python3

  local from="" name="" domain="" project_path=""
  local http_port="auto" socket_port="auto"
  local copy_storage=0 copy_db=0 ssl=1 dry_run=0 auto_yes=0
  local tmp_sql="" committed=0 nginx_created=0

  for arg in "$@"; do
    case "$arg" in
      --from=*) from="${arg#*=}" ;;
      --name=*) name="${arg#*=}" ;;
      --domain=*) domain="${arg#*=}" ;;
      --path=*) project_path="${arg#*=}" ;;
      --http-port=*) http_port="${arg#*=}" ;;
      --socket-port=*) socket_port="${arg#*=}" ;;
      --copy-storage) copy_storage=1 ;;
      --copy-db) copy_db=1 ;;
      --no-ssl) ssl=0 ;;
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  [[ -n "$from" && -n "$name" && -n "$domain" ]] || die "Thiếu --from, --name hoặc --domain"

  local src_path src_db db_name docker_identity
  src_path="$(inventory_get_field "$from" path)"
  src_db="$(inventory_get_field "$from" database)"

  site_step 1 "Validate Inventory và source strategy"
  [[ -d "$src_path" ]] || die "Site nguồn không tồn tại: $from"
  platform_git_verify "$src_path"
  platform_nginx_validate_domain "$domain"
  site_assert_name_available "$name"
  site_assert_domain_available "$domain"

  project_path="${project_path:-$(site_projects_root)/$(site_slugify "$name")}"
  [[ ! -e "$project_path" ]] || die "Path đã tồn tại: $project_path"

  site_step 2 "Allocate target identity"
  http_port="$(site_choose_port "$http_port" 8081)"
  socket_port="$(site_choose_port "$socket_port" 6001)"
  db_name="db_$(site_slugify "$name" | tr '-' '_')"
  docker_identity="$(site_slugify "$name")"

  echo "Strategy    : duplicate-live"
  echo "Source      : $from ($src_path)"
  echo "Destination : $project_path"
  echo "Name        : $name"
  echo "Domain      : $domain"
  echo "HTTP port   : $http_port"
  echo "Socket port : $socket_port"
  echo "Database    : $db_name"
  echo "Docker name : $docker_identity"
  echo "Copy DB     : $copy_db"
  echo "Copy storage: $copy_storage"
  echo "SSL         : $ssl"

  [[ "$dry_run" -eq 0 ]] || { echo "[DRY-RUN] Không thay đổi hệ thống."; return 0; }
  [[ "$auto_yes" -eq 1 ]] || site_confirm "Duplicate Laravel site?" || die "Đã hủy."

  trap 'rc=$?; if [[ $rc -ne 0 && $committed -eq 0 ]]; then
          [[ -n "$tmp_sql" ]] && rm -f "$tmp_sql" || true
          site_provision_cleanup_new_target "$project_path" "$domain" "$nginx_created"
        fi
        exit $rc' ERR

  site_step 3 "Source strategy: copy application files"
  mkdir -p "$project_path"
  rsync -a \
    --exclude='.git' \
    --exclude='vendor' \
    --exclude='node_modules' \
    --exclude='.docker-platform/state' \
    --exclude='storage/logs/*' \
    "$src_path/" "$project_path/"

  site_step 4 "Source strategy: copy Git metadata"
  platform_git_copy_metadata "$src_path" "$project_path"
  echo "[OK] Git HEAD: $(platform_git_commit_short "$project_path")"
  echo "[OK] Git remote: $(platform_git_remote "$project_path")"

  site_step 5 "Provision target environment"
  site_provision_configure_target \
    "$project_path" "$name" "$domain" "$db_name" \
    "$http_port" "$socket_port" 1

  if [[ "$copy_storage" -eq 0 && -d "$project_path/storage/app/public" ]]; then
    find "$project_path/storage/app/public" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi

  site_step 6 "Provision runtime prepare"
  site_provision_prepare_runtime "$name" "$project_path" 0 120

  if [[ "$copy_db" -eq 1 ]]; then
    site_step 7 "Source strategy: export live database"
    [[ -n "$src_db" ]] || die "Inventory site nguồn thiếu database."
    [[ -x "$src_path/platform-cli" ]] || die "Site nguồn thiếu platform-cli."
    [[ -x "$project_path/platform-cli" ]] || die "Site đích thiếu platform-cli."

    tmp_sql="/tmp/${src_db}_to_${db_name}_$$.sql"
    PROJECT_DIR="$src_path" "$src_path/platform-cli" db export "$tmp_sql"
    [[ -s "$tmp_sql" ]] || die "DB dump rỗng hoặc không tồn tại: $tmp_sql"

    site_step 8 "Source strategy: import target database"
    PROJECT_DIR="$project_path" "$project_path/platform-cli" db import "$tmp_sql" <<<"y"
    rm -f "$tmp_sql"
    tmp_sql=""
  else
    site_step 7 "Skip DB export (--copy-db không bật)"
    site_step 8 "Skip DB import (--copy-db không bật)"
  fi

  site_step 9 "Provision runtime finalize"
  site_provision_finalize_runtime "$project_path"

  site_step 10 "Provision Nginx"
  platform_nginx_ensure_proxy "$domain" "$http_port"
  nginx_created=1

  site_step 11 "Provision SSL + health"
  if [[ "$ssl" -eq 1 ]]; then
    if platform_ssl_exists "$domain"; then
      platform_ssl_verify "$domain"
      echo "[OK] SSL đã tồn tại: $domain"
    else
      platform_ssl_issue "$domain"
    fi
  else
    echo "[INFO] SSL skipped."
  fi
  site_provision_health "$project_path"

  site_step 12 "Inventory commit"
  site_provision_commit_inventory "$name" "$project_path"

  committed=1
  trap - ERR

  success "Duplicate thành công: $name"
  site_duplicate_report "$from" "$name" "$domain" "$http_port" "$socket_port" "$db_name"
}
