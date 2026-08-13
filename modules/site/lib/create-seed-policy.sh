#!/usr/bin/env bash

# Create-site database seed policy.
# Production create MUST NOT run DatabaseSeeder / `php artisan db:seed` globally.
# It reuses the same production-safe allow-list as `platform site production-seed`.

site_create_seed_repository() {
  local project_path="$1" compose_file="$2"
  echo "[CREATE SEED] Production allow-list"
  site_production_seed_repository_path "$project_path" "$compose_file"
}

site_create_seed_platform() {
  local project_path="$1"
  echo "[CREATE SEED] Production allow-list"
  site_production_seed_platform_path "$project_path"
}

# Override repository create finalize only inside the create command process.
site_create_repository_finalize() {
  local project_path="$1" compose_file="$2"

  site_create_repository_compose "$project_path" "$compose_file" \
    exec -T app php artisan migrate --force

  site_create_seed_repository "$project_path" "$compose_file"

  site_create_repository_compose "$project_path" "$compose_file" \
    exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
  site_create_repository_compose "$project_path" "$compose_file" \
    exec -T app php artisan config:cache
  site_create_repository_compose "$project_path" "$compose_file" \
    exec -T app php artisan route:cache || warn "route:cache thất bại; tiếp tục."
  site_create_repository_compose "$project_path" "$compose_file" \
    exec -T app php artisan view:cache || warn "view:cache thất bại; tiếp tục."
}

# Override shared provision finalize only inside the create command process.
site_provision_finalize_runtime() {
  local project_path="$1"

  deploy_migrate_path "$project_path"
  site_create_seed_platform "$project_path"
  deploy_optimize_path "$project_path"
  deploy_health_path "$project_path"
}
