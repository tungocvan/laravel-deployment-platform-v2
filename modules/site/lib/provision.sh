#!/usr/bin/env bash
#
# Shared Site Provisioning Engine
#
# This library owns COMMON target lifecycle steps only.
# Source strategies (duplicate/restore/create) own how application data arrives.
#

site_provision_set_env_value() {
  local file="$1" key="$2" value="$3" escaped
  escaped="$(printf '%s' "$value" | sed 's/[&|]/\\&/g')"
  touch "$file"

  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

site_provision_configure_target() {
  local project_path="$1"
  local name="$2"
  local domain="$3"
  local database="$4"
  local http_port="$5"
  local socket_port="$6"
  local rotate_secrets="${7:-1}"

  [[ -d "$project_path" ]] || die "Provision target path không tồn tại: $project_path"
  [[ -n "$name" ]] || die "Provision target name rỗng."
  [[ -n "$domain" ]] || die "Provision target domain rỗng."
  [[ -n "$database" ]] || die "Provision target database rỗng."

  local docker_identity
  docker_identity="$(site_slugify "$name")"
  [[ -n "$docker_identity" ]] || die "Không tạo được Docker identity."

  if [[ ! -f "$project_path/.env" ]]; then
    [[ -f "$project_path/.env.example" ]] || die "Thiếu .env và .env.example: $project_path"
    cp "$project_path/.env.example" "$project_path/.env"
  fi

  if [[ ! -f "$project_path/.docker-platform.env" ]]; then
    if [[ -f "$project_path/.docker-platform.env.example" ]]; then
      cp "$project_path/.docker-platform.env.example" "$project_path/.docker-platform.env"
    else
      touch "$project_path/.docker-platform.env"
    fi
  fi

  site_provision_set_env_value "$project_path/.env" APP_URL "https://$domain"
  site_provision_set_env_value "$project_path/.env" DB_DATABASE "$database"

  if [[ "$rotate_secrets" -eq 1 ]]; then
    require_command openssl
    site_provision_set_env_value "$project_path/.env" APP_KEY "base64:$(openssl rand -base64 32)"
    site_provision_set_env_value "$project_path/.env" BRIDGE_SECRET_KEY "$(openssl rand -hex 32)"
  fi

  site_provision_set_env_value "$project_path/.docker-platform.env" COMPOSE_PROJECT_NAME "$docker_identity"
  site_provision_set_env_value "$project_path/.docker-platform.env" HTTP_PORT "$http_port"
  site_provision_set_env_value "$project_path/.docker-platform.env" SOCKET_PORT "$socket_port"

  echo "[OK] Provision target configured: $name"
}

site_provision_prepare_runtime() {
  local name="$1" project_path="$2" no_build="${3:-0}" timeout="${4:-120}"
  deploy_prepare_path "$(site_slugify "$name")" "$project_path" "$no_build" "$timeout"
}

site_provision_finalize_runtime() {
  local project_path="$1"
  deploy_finalize_path "$project_path"
}

site_provision_configure_web() {
  local domain="$1" http_port="$2" use_ssl="${3:-1}"

  platform_nginx_ensure_proxy "$domain" "$http_port"

  if [[ "$use_ssl" -eq 1 ]]; then
    platform_ssl_ensure "$domain"
  else
    echo "[INFO] SSL skipped."
  fi
}

site_provision_health() {
  local project_path="$1"
  deploy_health_path "$project_path"
}

site_provision_commit_inventory() {
  local name="$1" project_path="$2"
  inventory_sync "$name" --name="$name" --path="$project_path"
}

site_provision_cleanup_new_target() {
  local project_path="$1"
  local domain="$2"
  local nginx_created="${3:-0}"

  warn "Provision thất bại. Đang rollback target..."

  if [[ -n "$project_path" && -d "$project_path" ]]; then
    deploy_compose "$project_path" down -v --remove-orphans >/dev/null 2>&1 || true
  fi

  if [[ "$nginx_created" -eq 1 ]]; then
    # Remove Nginx first; SSL module refuses to delete cert while Nginx references it.
    platform_nginx_remove "$domain" >/dev/null 2>&1 || true
    # Only remove cert if it belongs to this exact domain and is now unused.
    platform_ssl_remove "$domain" >/dev/null 2>&1 || true
  fi

  [[ -n "$project_path" && -d "$project_path" ]] && rm -rf "$project_path" || true
}
