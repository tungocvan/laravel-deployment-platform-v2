#!/usr/bin/env bash

# Create-site-only database seed policy.
# This library is sourced only by `platform site create`, so normal deploy/update
# continues to run migrate + optimize without executing seeders.

site_create_seed_repository() {
  local project_path="$1" compose_file="$2"
  echo "[CREATE SEED] Laravel db:seed --force"
  site_create_repository_compose "$project_path" "$compose_file" \
    exec -T app php artisan db:seed --force
}

site_create_seed_platform() {
  local project_path="$1"
  echo "[CREATE SEED] Laravel db:seed --force"
  deploy_compose "$project_path" exec -T app php artisan db:seed --force
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
# Other commands still use deploy_finalize_path() unchanged and therefore do not seed.
site_provision_finalize_runtime() {
  local project_path="$1"

  deploy_migrate_path "$project_path"
  site_create_seed_platform "$project_path"
  deploy_optimize_path "$project_path"
  deploy_health_path "$project_path"
}
