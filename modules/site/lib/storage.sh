#!/usr/bin/env bash

site_storage_context() {
  local key="$1"
  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"

  SITE_STORAGE_NAME="$(inventory_get_field "$key" name)"
  SITE_STORAGE_PATH="$(inventory_get_field "$key" path)"
  SITE_STORAGE_STRATEGY="$(inventory_get_field "$key" runtime_strategy 2>/dev/null || true)"
  SITE_STORAGE_STRATEGY="${SITE_STORAGE_STRATEGY:-platform}"
  SITE_STORAGE_COMPOSE="$(inventory_get_field "$key" compose_file 2>/dev/null || true)"
  SITE_STORAGE_COMPOSE="${SITE_STORAGE_COMPOSE:-compose.yaml}"

  [[ -d "$SITE_STORAGE_PATH" ]] || die "Project path không tồn tại: $SITE_STORAGE_PATH"
}

site_storage_compose() {
  case "$SITE_STORAGE_STRATEGY" in
    repository) site_create_repository_compose "$SITE_STORAGE_PATH" "$SITE_STORAGE_COMPOSE" "$@" ;;
    platform|"") deploy_compose "$SITE_STORAGE_PATH" "$@" ;;
    *) die "Runtime strategy không hỗ trợ storage operation: $SITE_STORAGE_STRATEGY" ;;
  esac
}

site_storage_validate_relative() {
  local relative="${1:-}"
  [[ -n "$relative" ]] || die "Storage path bắt buộc."
  [[ "$relative" != /* ]] || die "Storage path phải tương đối trong storage/: $relative"
  [[ "$relative" != *".."* ]] || die "Storage path không được chứa '..': $relative"
}

site_storage_status() {
  local key="$1"
  require_root
  site_storage_context "$key"

  echo "Site       : $SITE_STORAGE_NAME"
  echo "Path       : $SITE_STORAGE_PATH"
  echo "Strategy   : $SITE_STORAGE_STRATEGY"
  echo
  echo "===== APP STORAGE ====="
  site_storage_compose exec -T app sh -lc '
    set -e
    ls -ld storage storage/app storage/app/public storage/framework storage/logs 2>&1 || true
    echo "PUBLIC LINK:"
    ls -ld public/storage 2>&1 || true
    readlink public/storage 2>/dev/null || true
    echo "WRITE TEST AS WWW-DATA:"
    su -s /bin/sh www-data -c "test -w storage/app/public && echo WRITABLE || echo NOT_WRITABLE"
  '
  echo
  echo "===== WEB STORAGE ====="
  site_storage_compose exec -T web sh -lc '
    ls -ld /var/www/html/storage /var/www/html/storage/app/public 2>&1 || true
    ls -ld /var/www/html/public/storage 2>&1 || true
    readlink /var/www/html/public/storage 2>/dev/null || true
  '
}

site_storage_repair() {
  local key="$1"
  require_root
  site_storage_context "$key"

  echo "[STORAGE] Repair persistent storage: $SITE_STORAGE_NAME"
  site_storage_compose exec -T app sh -lc '
    set -e
    mkdir -p storage/app/public storage/framework/cache storage/framework/sessions storage/framework/views storage/logs bootstrap/cache
    chown -R www-data:www-data storage bootstrap/cache
    find storage -type d -exec chmod 0775 {} \;
    find storage -type f -exec chmod ug+rw {} \;
    chmod 0775 bootstrap/cache
    if [ -L public/storage ]; then
      target="$(readlink public/storage || true)"
      [ "$target" = "/var/www/html/storage/app/public" ] || { rm -f public/storage; ln -s /var/www/html/storage/app/public public/storage; }
    elif [ -e public/storage ]; then
      echo "[ERROR] public/storage tồn tại nhưng không phải symlink" >&2
      exit 3
    else
      ln -s /var/www/html/storage/app/public public/storage
    fi
  '
  site_storage_compose exec -T web sh -lc '
    test -L /var/www/html/public/storage || { echo "[ERROR] web public/storage symlink missing" >&2; exit 4; }
    test "$(readlink /var/www/html/public/storage)" = "/var/www/html/storage/app/public"
  '
  success "Storage permissions/link đã repair: $SITE_STORAGE_NAME"
}

site_storage_list() {
  local key="$1" relative="${2:-app/public}"
  require_root
  site_storage_validate_relative "$relative"
  site_storage_context "$key"

  site_storage_compose exec -T app sh -lc '
    set -e
    relative="$1"
    target="storage/$relative"
    [ -e "$target" ] || { echo "[ERROR] Không tồn tại: $target" >&2; exit 5; }
    ls -lah "$target"
  ' sh "$relative"
}

site_storage_put() {
  local key="$1" source="$2" relative="$3"
  require_root
  [[ -f "$source" ]] || die "Source file không tồn tại trên VPS: $source"
  site_storage_validate_relative "$relative"
  site_storage_context "$key"

  echo "[STORAGE] Put file: $source -> storage/$relative"
  cat "$source" | site_storage_compose exec -T app sh -lc '
    set -e
    relative="$1"
    target="storage/$relative"
    mkdir -p "$(dirname "$target")"
    cat > "$target"
    chown www-data:www-data "$target" 2>/dev/null || true
    chmod ug+rw "$target" 2>/dev/null || true
    ls -lah "$target"
  ' sh "$relative"
}

site_storage_command() {
  local key="${1:-}" action="${2:-}"; shift 2 || true
  [[ -n "$key" && -n "$action" ]] || die "USAGE: platform site storage <site> <status|repair|list|put> ..."

  case "$action" in
    status) site_storage_status "$key" ;;
    repair) site_storage_repair "$key" ;;
    list) site_storage_list "$key" "${1:-app/public}" ;;
    put)
      local source="" relative="" arg
      for arg in "$@"; do
        case "$arg" in
          --source=*) source="${arg#*=}" ;;
          --path=*) relative="${arg#*=}" ;;
          *) die "Option không hợp lệ: $arg" ;;
        esac
      done
      [[ -n "$source" && -n "$relative" ]] || die "USAGE: platform site storage <site> put --source=/path/file --path=app/public/file"
      site_storage_put "$key" "$source" "$relative"
      ;;
    *) die "Storage action không hợp lệ: $action" ;;
  esac
}
