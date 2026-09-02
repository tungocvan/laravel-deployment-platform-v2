#!/usr/bin/env bash

# Public-storage runtime contract for managed Docker sites.
# PHP keeps ownership/write access while the separate web container must be
# able to traverse storage/app and read files below storage/app/public.

deploy_storage_normalize_path() {
  local project_dir="$1"

  deploy_step "STORAGE" "Normalize Laravel public storage permissions"
  deploy_compose "$project_dir" exec -T app sh -lc '
    set -eu
    cd /var/www/html

    mkdir -p storage/app storage/app/public

    owner="$(stat -c "%u:%g" storage/app)"
    chown -R "$owner" storage/app/public

    # Keep storage/app private while allowing the web container to traverse it.
    chmod 2711 storage/app

    # Public disk must be readable/traversable by Nginx through public/storage.
    find storage/app/public -type d -exec chmod 2755 {} \;
    find storage/app/public -type f -exec chmod 0644 {} \;
  '

  deploy_storage_verify_path "$project_dir"
}

deploy_storage_verify_path() {
  local project_dir="$1"
  # Do not use a dotfile here: production Nginx commonly denies requests to
  # hidden files by design, which would create a false-negative storage probe.
  local probe="platform-storage-health-$$.txt"

  deploy_compose "$project_dir" exec -T app sh -lc \
    "set -eu; printf '%s\\n' platform-storage-ok > /var/www/html/storage/app/public/$probe; chmod 0644 /var/www/html/storage/app/public/$probe"

  deploy_compose "$project_dir" exec -T app sh -lc \
    "printf '[INFO] storage/app mode=%s\\n' \"\$(stat -c '%a' /var/www/html/storage/app)\"; printf '[INFO] storage/app/public mode=%s\\n' \"\$(stat -c '%a' /var/www/html/storage/app/public)\"; printf '[INFO] probe mode=%s\\n' \"\$(stat -c '%a' /var/www/html/storage/app/public/$probe)\""

  if deploy_compose "$project_dir" exec -T web sh -lc \
    "wget -q -O - http://127.0.0.1:8080/storage/$probe | grep -Fxq platform-storage-ok"; then
    echo "[OK] Public storage: web container can serve /storage/*"
  else
    deploy_compose "$project_dir" exec -T app rm -f "/var/www/html/storage/app/public/$probe" >/dev/null 2>&1 || true
    die "Public storage verification failed: web container cannot serve /storage/*."
  fi

  deploy_compose "$project_dir" exec -T app rm -f "/var/www/html/storage/app/public/$probe"
}

deploy_storage_repair() {
  require_root
  local key="${1:-}" project_dir

  project_dir="$(deploy_resolve_path "$key")"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null
  deploy_storage_normalize_path "$project_dir"
  success "Public storage permissions đã được chuẩn hóa: $project_dir"
}
