#!/usr/bin/env bash
#
# Shared Site Provisioning Engine
#
# This library owns COMMON target lifecycle steps only.
# Source strategies (duplicate/restore/create) own how application data arrives.
#
# IMPORTANT ENV CONTRACT FOR DOCKER SITES
# ---------------------------------------
# When creating/provisioning a fresh managed Docker site, `.env` MUST be
# initialized from `.env.docker.example` when that file exists. This is the
# canonical Docker runtime template because it contains compose-network values
# such as DB_HOST=db, REDIS_HOST=redis and the variables required by compose.
#
# `.env.example` is only a compatibility fallback for repositories that do not
# provide `.env.docker.example`. Do not reverse this priority during refactors.
#
# ENV PERMISSION CONTRACT
# -----------------------
# Managed sites expose an admin ENV editor through PHP-FPM. Because `.env` is
# bind-mounted from the host into the app container, the host file must be
# writable by the PHP-FPM runtime group. Default runtime GID is 33 (www-data).
# Override with PLATFORM_APP_GID when an image uses a different runtime GID.
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

site_provision_env_value() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -n -E "s/^${key}=(.*)$/\1/p" "$file" | tail -n1
}

site_provision_random_secret() {
  require_command openssl
  openssl rand -hex 24
}

site_provision_apply_env_permissions() {
  local env_file="$1"
  local app_gid="${PLATFORM_APP_GID:-33}"

  [[ -f "$env_file" ]] || die "Không tìm thấy .env để phân quyền: $env_file"
  [[ "$app_gid" =~ ^[0-9]+$ ]] || die "PLATFORM_APP_GID không hợp lệ: $app_gid"

  chown "root:${app_gid}" "$env_file"
  chmod 0660 "$env_file"

  echo "[OK] Environment permissions: root:${app_gid} 0660"
}

site_provision_init_env() {
  local project_path="$1" env_file="$project_path/.env"

  [[ ! -f "$env_file" ]] || return 0

  if [[ -f "$project_path/.env.docker.example" ]]; then
    cp "$project_path/.env.docker.example" "$env_file"
    echo "[INFO] Environment template: .env.docker.example"
    return 0
  fi

  if [[ -f "$project_path/.env.example" ]]; then
    warn ".env.docker.example không tồn tại; fallback sang .env.example."
    cp "$project_path/.env.example" "$env_file"
    echo "[INFO] Environment template: .env.example (fallback)"
    return 0
  fi

  die "Thiếu .env, .env.docker.example và .env.example: $project_path"
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

  local docker_identity env_file
  docker_identity="$(site_slugify "$name")"
  [[ -n "$docker_identity" ]] || die "Không tạo được Docker identity."
  env_file="$project_path/.env"

  site_provision_init_env "$project_path"

  if [[ ! -f "$project_path/.docker-platform.env" ]]; then
    if [[ -f "$project_path/.docker-platform.env.example" ]]; then
      cp "$project_path/.docker-platform.env.example" "$project_path/.docker-platform.env"
    else
      touch "$project_path/.docker-platform.env"
    fi
  fi

  site_provision_set_env_value "$env_file" APP_NAME "$name"
  site_provision_set_env_value "$env_file" APP_ENV "production"
  site_provision_set_env_value "$env_file" APP_DEBUG "false"
  site_provision_set_env_value "$env_file" APP_URL "https://$domain"

  local db_user db_password root_password redis_password
  db_user="$(site_provision_env_value "$env_file" DB_USERNAME || true)"
  [[ -n "$db_user" ]] || db_user="laravel"

  db_password="$(site_provision_env_value "$env_file" DB_PASSWORD || true)"
  root_password="$(site_provision_env_value "$env_file" MARIADB_ROOT_PASSWORD || true)"
  redis_password="$(site_provision_env_value "$env_file" REDIS_PASSWORD || true)"

  if [[ "$rotate_secrets" -eq 1 ]]; then
    db_password="$(site_provision_random_secret)"
    root_password="$(site_provision_random_secret)"
    redis_password="$(site_provision_random_secret)"
  else
    [[ -n "$db_password" && "$db_password" != "CHANGE_ME" ]] || db_password="$(site_provision_random_secret)"
    [[ -n "$root_password" && "$root_password" != "CHANGE_ME_ROOT" ]] || root_password="$(site_provision_random_secret)"
    [[ -n "$redis_password" && "$redis_password" != "null" && "$redis_password" != "CHANGE_ME_REDIS" ]] || redis_password="$(site_provision_random_secret)"
  fi

  site_provision_set_env_value "$env_file" DB_DATABASE "$database"
  site_provision_set_env_value "$env_file" DB_USERNAME "$db_user"
  site_provision_set_env_value "$env_file" DB_PASSWORD "$db_password"
  site_provision_set_env_value "$env_file" MARIADB_ROOT_PASSWORD "$root_password"
  site_provision_set_env_value "$env_file" REDIS_PASSWORD "$redis_password"

  if [[ "$rotate_secrets" -eq 1 ]]; then
    require_command openssl
    site_provision_set_env_value "$env_file" APP_KEY "base64:$(openssl rand -base64 32)"
    site_provision_set_env_value "$env_file" BRIDGE_SECRET_KEY "$(openssl rand -hex 32)"
  fi

  site_provision_set_env_value "$project_path/.docker-platform.env" COMPOSE_PROJECT_NAME "$docker_identity"
  site_provision_set_env_value "$project_path/.docker-platform.env" HTTP_PORT "$http_port"
  site_provision_set_env_value "$project_path/.docker-platform.env" SOCKET_PORT "$socket_port"

  site_provision_apply_env_permissions "$env_file"

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
    if platform_ssl_exists "$domain"; then
      platform_ssl_verify "$domain"
      echo "[OK] SSL đã tồn tại, giữ nguyên: $domain"
    else
      platform_ssl_issue "$domain"
    fi
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
    platform_nginx_remove "$domain" >/dev/null 2>&1 || true
    platform_ssl_remove "$domain" >/dev/null 2>&1 || true
  fi

  [[ -n "$project_path" && -d "$project_path" ]] && rm -rf "$project_path" || true
}
