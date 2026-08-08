#!/usr/bin/env bash

platform_nginx_available_dir() {
  printf '%s' "${NGINX_AVAILABLE_DIR:-/etc/nginx/sites-available}"
}

platform_nginx_enabled_dir() {
  printf '%s' "${NGINX_ENABLED_DIR:-/etc/nginx/sites-enabled}"
}

platform_nginx_backup_dir() {
  printf '%s' "${PLATFORM_HOME}/state/nginx-backups"
}

platform_nginx_template() {
  printf '%s' "${PLATFORM_HOME}/templates/nginx/laravel-proxy.conf.tpl"
}

platform_nginx_validate_domain() {
  local domain="${1:-}"
  [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,63}$ ]] \
    || die "Domain không hợp lệ: $domain"
}

platform_nginx_validate_port() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] || die "HTTP port không hợp lệ: $port"
  (( port >= 1 && port <= 65535 )) || die "HTTP port ngoài phạm vi: $port"
}

platform_nginx_config_path() {
  local domain="$1"
  printf '%s/%s' "$(platform_nginx_available_dir)" "$domain"
}

platform_nginx_enabled_path() {
  local domain="$1"
  printf '%s/%s' "$(platform_nginx_enabled_dir)" "$domain"
}

platform_nginx_is_managed_file() {
  local file="$1"
  [[ -f "$file" ]] && grep -q '^# Managed by Laravel Deployment Platform$' "$file"
}

platform_nginx_server_names_from_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -n -E 's/^[[:space:]]*server_name[[:space:]]+([^;]+);.*/\1/p' "$file" |
    tr ' ' '\n' |
    sed '/^$/d'
}

platform_nginx_conflict_files() {
  local domain="$1"
  platform_nginx_validate_domain "$domain"

  local dir file
  dir="$(platform_nginx_available_dir)"
  [[ -d "$dir" ]] || return 0

  for file in "$dir"/*; do
    [[ -f "$file" ]] || continue
    if platform_nginx_server_names_from_file "$file" | grep -Fxq "$domain"; then
      printf '%s\n' "$file"
    fi
  done
}

platform_nginx_conflicts() {
  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform nginx conflicts <domain>"

  local found=0 file
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    echo "$file"
    found=1
  done < <(platform_nginx_conflict_files "$domain")

  [[ "$found" -eq 1 ]] || echo "Không có conflict: $domain"
}

platform_nginx_backup_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  local backup_dir stamp
  backup_dir="$(platform_nginx_backup_dir)"
  stamp="$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$backup_dir"

  cp -a "$file" "$backup_dir/$(basename "$file").$stamp.bak"
  echo "[OK] Nginx backup: $backup_dir/$(basename "$file").$stamp.bak"
}

platform_nginx_render_content() {
  local domain="$1" port="$2"
  local template
  template="$(platform_nginx_template)"
  [[ -f "$template" ]] || die "Thiếu Nginx template: $template"

  sed \
    -e "s|{{DOMAIN}}|$domain|g" \
    -e "s|{{HTTP_PORT}}|$port|g" \
    "$template"
}

platform_nginx_assert_no_foreign_conflict() {
  local domain="$1" target="$2"
  local file

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue

    if [[ "$(readlink -f "$file")" == "$(readlink -m "$target")" ]]; then
      continue
    fi

    die "server_name '$domain' đã tồn tại trong config khác: $file"
  done < <(platform_nginx_conflict_files "$domain")
}

platform_nginx_render() {
  require_root
  require_command nginx

  local domain="${1:-}" port="${2:-}"
  [[ -n "$domain" && -n "$port" ]] || die "USAGE: platform nginx render <domain> <http-port>"

  platform_nginx_validate_domain "$domain"
  platform_nginx_validate_port "$port"

  local available target tmp
  available="$(platform_nginx_available_dir)"
  target="$(platform_nginx_config_path "$domain")"

  mkdir -p "$available" "$(platform_nginx_enabled_dir)" "$(platform_nginx_backup_dir)"

  platform_nginx_assert_no_foreign_conflict "$domain" "$target"

  if [[ -f "$target" ]]; then
    # Never silently replace an unrelated legacy config.
    if ! platform_nginx_is_managed_file "$target"; then
      local declared
      declared="$(platform_nginx_server_names_from_file "$target" | tr '\n' ' ')"
      die "Config đã tồn tại nhưng không do Platform quản lý: $target (server_name: ${declared:-unknown})"
    fi
    platform_nginx_backup_file "$target"
  fi

  tmp="$(mktemp "${target}.tmp.XXXXXX")"
  platform_nginx_render_content "$domain" "$port" > "$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$target"

  echo "[OK] Nginx rendered: $target"
}

platform_nginx_enable() {
  require_root
  require_command nginx

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform nginx enable <domain>"
  platform_nginx_validate_domain "$domain"

  local target enabled
  target="$(platform_nginx_config_path "$domain")"
  enabled="$(platform_nginx_enabled_path "$domain")"

  [[ -f "$target" ]] || die "Config chưa tồn tại: $target"

  ln -sfn "$target" "$enabled"

  nginx -t
  systemctl reload nginx

  echo "[OK] Nginx enabled: $domain"
}

platform_nginx_disable() {
  require_root
  require_command nginx

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform nginx disable <domain>"
  platform_nginx_validate_domain "$domain"

  rm -f "$(platform_nginx_enabled_path "$domain")"

  nginx -t
  systemctl reload nginx

  echo "[OK] Nginx disabled: $domain"
}

platform_nginx_ensure() {
  require_root
  local domain="${1:-}" port="${2:-}"
  [[ -n "$domain" && -n "$port" ]] || die "USAGE: platform nginx ensure <domain> <http-port>"

  platform_nginx_render "$domain" "$port"
  platform_nginx_enable "$domain"
}

platform_nginx_ensure_proxy() {
  platform_nginx_ensure "$@"
}

platform_nginx_show() {
  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform nginx show <domain>"
  platform_nginx_validate_domain "$domain"

  local file
  file="$(platform_nginx_config_path "$domain")"
  [[ -f "$file" ]] || die "Không tìm thấy config: $file"
  cat "$file"
}

platform_nginx_verify() {
  require_command nginx
  nginx -t
}

platform_nginx_remove() {
  require_root
  require_command nginx

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform nginx remove <domain>"
  platform_nginx_validate_domain "$domain"

  local target enabled
  target="$(platform_nginx_config_path "$domain")"
  enabled="$(platform_nginx_enabled_path "$domain")"

  if [[ -f "$target" ]] && ! platform_nginx_is_managed_file "$target"; then
    die "Từ chối remove config không do Platform quản lý: $target"
  fi

  [[ -f "$target" ]] && platform_nginx_backup_file "$target"

  rm -f "$enabled"
  rm -f "$target"

  nginx -t
  systemctl reload nginx

  echo "[OK] Nginx removed: $domain"
}
