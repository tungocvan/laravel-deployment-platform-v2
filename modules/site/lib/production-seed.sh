#!/usr/bin/env bash

# Production-safe database synchronization.
# This deliberately does NOT run DatabaseSeeder / db:seed globally.
# Only explicitly allow-listed, idempotent production metadata seeders belong here.

site_production_seed_repository_path() {
  local project_path="$1" compose_file="${2:-compose.yaml}"

  if [[ ! -f "$project_path/Modules/Role/database/seeders/RolesAndPermissionsSeeder.php" ]]; then
    echo "[PRODUCTION SEED] RolesAndPermissionsSeeder không tồn tại; bỏ qua permission sync."
    return 0
  fi

  echo "[PRODUCTION SEED] Sync roles & permissions"
  site_create_repository_compose "$project_path" "$compose_file" exec -T app \
    php artisan db:seed --class='Modules\Role\database\seeders\RolesAndPermissionsSeeder' --force

  echo "[PRODUCTION SEED] Reset Spatie permission cache"
  site_create_repository_compose "$project_path" "$compose_file" exec -T app \
    php artisan permission:cache-reset
}

site_production_seed_platform_path() {
  local project_path="$1"

  if [[ ! -f "$project_path/Modules/Role/database/seeders/RolesAndPermissionsSeeder.php" ]]; then
    echo "[PRODUCTION SEED] RolesAndPermissionsSeeder không tồn tại; bỏ qua permission sync."
    return 0
  fi

  echo "[PRODUCTION SEED] Sync roles & permissions"
  deploy_compose "$project_path" exec -T app \
    php artisan db:seed --class='Modules\Role\database\seeders\RolesAndPermissionsSeeder' --force

  echo "[PRODUCTION SEED] Reset Spatie permission cache"
  deploy_compose "$project_path" exec -T app \
    php artisan permission:cache-reset
}

site_production_seed_repository() {
  local key="$1" project_path="$2"
  local compose_file
  compose_file="$(inventory_get_field "$key" compose_file 2>/dev/null || true)"
  compose_file="${compose_file:-compose.yaml}"
  site_production_seed_repository_path "$project_path" "$compose_file"
}

site_production_seed_platform() {
  site_production_seed_platform_path "$1"
}

site_production_seed() {
  local key="$1"
  local project_path strategy

  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"
  project_path="$(inventory_get_field "$key" path)"
  strategy="$(inventory_get_field "$key" runtime_strategy 2>/dev/null || true)"
  strategy="${strategy:-platform}"

  [[ -d "$project_path" ]] || die "Project path không tồn tại: $project_path"

  case "$strategy" in
    repository) site_production_seed_repository "$key" "$project_path" ;;
    platform|"") site_production_seed_platform "$project_path" ;;
    *) die "Runtime strategy không hỗ trợ production seed: $strategy" ;;
  esac

  success "Production Seed / Sync Permissions hoàn tất: $key"
}
