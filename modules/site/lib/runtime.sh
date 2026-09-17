#!/usr/bin/env bash

# Shared production runtime adapter. Runtime details are discovered live; Inventory
# remains the source of known managed-site identity/path metadata.
site_runtime_path() {
  local site="$1" path
  path="$(inventory_get_field "$site" path 2>/dev/null || true)"
  [[ -n "$path" && -d "$path" ]] || die "Không tìm thấy managed site/path: $site"
  readlink -f "$path"
}

site_runtime_compose_project() {
  local site="$1" path="$2" value
  value="$(deploy_env_get "$path/.docker-platform.env" COMPOSE_PROJECT_NAME 2>/dev/null || true)"
  [[ -n "$value" && "$value" != "laravel-app" ]] || value="$(deploy_resolve_identity "$site" "$path")"
  printf '%s\n' "$value"
}

site_runtime_services() {
  local path="$1"
  deploy_compose "$path" config --services 2>/dev/null
}

site_runtime_app_service() {
  local path="$1" services
  services="$(site_runtime_services "$path" || true)"
  for candidate in app php php-fpm laravel; do
    grep -Fxq "$candidate" <<<"$services" && { printf '%s\n' "$candidate"; return 0; }
  done
  die "Không xác định được Laravel app service từ Compose topology."
}

site_runtime_capabilities() {
  local path="$1" helper
  for helper in production-debug.sh run-docker-artisan.sh run-updated-env.sh production-cleanup.sh; do
    if [[ -x "$path/$helper" ]]; then
      printf '%s\tpresent\n' "$helper"
    else
      printf '%s\tabsent (native fallback)\n' "$helper"
    fi
  done
}

site_runtime_status() {
  local site="$1" path project services app
  path="$(site_runtime_path "$site")"
  project="$(site_runtime_compose_project "$site" "$path")"
  services="$(site_runtime_services "$path" || true)"
  app="$(site_runtime_app_service "$path" 2>/dev/null || true)"

  echo "========================================================="
  echo "PRODUCTION RUNTIME STATUS"
  echo "========================================================="
  echo "Site            : $site"
  echo "Project path    : $path"
  echo "Compose project : $project"
  echo "App service     : ${app:-unknown}"
  echo
  echo "----- DISCOVERED SERVICES -----"
  if [[ -n "$services" ]]; then printf '%s\n' "$services" | sed 's/^/  - /'; else echo "  (none)"; fi
  echo
  echo "----- CONTAINERS / HEALTH / PORTS -----"
  deploy_compose "$path" ps -a || true
  echo
  echo "----- CAPABILITIES -----"
  site_runtime_capabilities "$path"
}

site_runtime_artisan() {
  local site="$1"; shift
  [[ "$#" -gt 0 ]] || die "Thiếu Artisan command."
  local path app command
  path="$(site_runtime_path "$site")"
  app="$(site_runtime_app_service "$path")"
  command="$1"
  case "$command" in
    migrate:fresh|db:wipe)
      die "Artisan command bị BLOCK trong Production Site Operations: $command"
      ;;
  esac
  deploy_compose "$path" exec -T "$app" php artisan "$@"
}

site_runtime_health() {
  local site="$1" path app
  path="$(site_runtime_path "$site")"
  app="$(site_runtime_app_service "$path")"
  deploy_compose "$path" exec -T "$app" php artisan --version >/dev/null
  deploy_compose "$path" ps -a
}
