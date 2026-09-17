#!/usr/bin/env bash

site_ops_git_changed_files() { local path="$1" from="$2" to="$3"; git -C "$path" diff --name-only "$from..$to" 2>/dev/null || true; }
site_ops_requires_build() { grep -Eq '(^|/)(package(-lock)?\.json|pnpm-lock\.yaml|yarn\.lock|vite\.config\.|resources/|Dockerfile|compose[^/]*\.ya?ml)' <<<"$1"; }
site_ops_has_migrations() { grep -Eq '(^|/)database/migrations/' <<<"$1"; }

# Docker Compose records the exact config files used to create a container in
# com.docker.compose.project.config_files. Treat an untracked overlay as
# runtime-managed only when a live container for this exact Compose project
# proves that the exact file path is part of its runtime config.
site_ops_runtime_config_files() {
  local site="$1" path="$2" project ids id labels raw file
  command -v docker >/dev/null 2>&1 || return 0
  project="$(site_runtime_compose_project "$site" "$path" 2>/dev/null || true)"
  [[ -n "$project" ]] || return 0
  ids="$(docker ps -aq --filter "label=com.docker.compose.project=$project" 2>/dev/null || true)"
  [[ -n "$ids" ]] || return 0
  for id in $ids; do
    labels="$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project.config_files" }}' "$id" 2>/dev/null || true)"
    [[ -n "$labels" && "$labels" != '<no value>' ]] || continue
    while IFS= read -r raw; do
      [[ -n "$raw" ]] || continue
      if [[ "$raw" = /* ]]; then file="$raw"; else file="$path/$raw"; fi
      [[ -e "$file" ]] || continue
      readlink -f "$file" 2>/dev/null || true
    done < <(printf '%s' "$labels" | tr ',' '\n')
  done | sort -u
}

site_ops_runtime_owned_overlay() {
  local path="$1" candidate="$2" runtime_files="$3" absolute
  [[ "$candidate" =~ (^|/)compose[^/]*\.ya?ml$ ]] || return 1
  [[ -f "$path/$candidate" ]] || return 1
  absolute="$(readlink -f "$path/$candidate" 2>/dev/null || true)"
  [[ -n "$absolute" ]] || return 1
  grep -Fxq "$absolute" <<<"$runtime_files"
}

site_ops_dirty_report() {
  local site="$1" path="$2" status tracked untracked runtime_files managed="" blocking="" file
  status="$(git -C "$path" status --porcelain --untracked-files=all)"
  [[ -n "$status" ]] || return 1
  tracked="$(printf '%s\n' "$status" | awk 'substr($0,1,2) != "??" {print substr($0,4)}')"
  untracked="$(printf '%s\n' "$status" | awk 'substr($0,1,2) == "??" {print substr($0,4)}')"
  runtime_files="$(site_ops_runtime_config_files "$site" "$path")"

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if site_ops_runtime_owned_overlay "$path" "$file" "$runtime_files"; then
      managed+="${managed:+$'\n'}$file"
    else
      blocking+="${blocking:+$'\n'}$file"
    fi
  done <<<"$untracked"

  if [[ -n "$managed" ]]; then
    echo "RUNTIME-MANAGED OVERLAYS (verified from live Docker Compose labels):"
    printf '%s\n' "$managed" | sed 's/^/  - /'
    echo "[OK] Các overlay này được giữ nguyên và không làm BLOCK Update Site."
  fi

  [[ -z "$tracked" && -z "$blocking" ]] && return 1
  echo "========================================================="
  echo "UPDATE SITE — BLOCKED: WORKING TREE NOT CLEAN"
  echo "========================================================="
  if [[ -n "$tracked" ]]; then echo "TRACKED MODIFIED / STAGED:"; printf '%s\n' "$tracked" | sed 's/^/  - /'; fi
  if [[ -n "$blocking" ]]; then echo "UNTRACKED (NOT VERIFIED AS RUNTIME-MANAGED):"; printf '%s\n' "$blocking" | sed 's/^/  - /'; fi
  echo "Không tự git add, git clean hoặc xóa các file trên."
  echo "Update bị BLOCK để bảo vệ local changes và runtime overlays chưa xác minh."
  return 0
}

site_ops_update() {
  require_root
  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform site update <site> [--dry-run] [--migrate] [--yes]"
  local dry=0 migrate=0 yes=0 arg
  for arg in "$@"; do case "$arg" in --dry-run) dry=1;; --migrate) migrate=1;; --yes) yes=1;; *) die "Option không hợp lệ: $arg";; esac; done
  local path branch before upstream after changed build=0 migration_risk=0
  path="$(site_runtime_path "$site")"; platform_git_trust "$path"
  if site_ops_dirty_report "$site" "$path"; then return 2; fi
  branch="$(git -C "$path" branch --show-current)"; [[ -n "$branch" ]] || die "Detached HEAD. Update bị BLOCK."
  before="$(git -C "$path" rev-parse HEAD)"; git -C "$path" fetch --prune origin; upstream="origin/$branch"
  git -C "$path" rev-parse --verify "$upstream" >/dev/null 2>&1 || die "Không tìm thấy upstream: $upstream"
  after="$(git -C "$path" rev-parse "$upstream")"; changed="$(site_ops_git_changed_files "$path" "$before" "$after")"
  site_ops_requires_build "$changed" && build=1 || true; site_ops_has_migrations "$changed" && migration_risk=1 || true
  echo "========================================================="; echo "UPDATE SITE PLAN"; echo "========================================================="
  echo "Site          : $site"; echo "Branch        : $branch"; echo "Current       : $before"; echo "Upstream      : $after"
  echo "Build needed  : $build"; echo "Migration risk: $migration_risk"; echo "Run migration : $migrate"; echo "Changed files :"
  if [[ -n "$changed" ]]; then printf '%s\n' "$changed" | sed 's/^/  /'; else echo "  (none)"; fi
  [[ "$before" != "$after" ]] || { echo "[OK] Site đã ở upstream mới nhất."; return 0; }
  if [[ "$migration_risk" -eq 1 && "$migrate" -eq 0 ]]; then echo "[BLOCKED] Có migration mới. Chỉ chạy khi operator chủ động thêm --migrate."; return 2; fi
  [[ "$dry" -eq 0 ]] || { echo "[DRY-RUN] Không thay đổi source/runtime."; return 0; }
  [[ "$yes" -eq 1 ]] || site_confirm "Apply production update?" || die "Đã hủy."
  if [[ "$migration_risk" -eq 1 ]]; then echo "[CHECKPOINT] Creating verified backup before migration..."; backup_create "$site" >/dev/null; fi
  git -C "$path" merge --ff-only "$upstream"
  deploy_ensure_identity_path "$site" "$path" >/dev/null; deploy_preflight "$path"
  if [[ "$build" -eq 1 ]]; then deploy_compose "$path" build; fi
  deploy_compose "$path" up -d --remove-orphans; deploy_wait_database "$path" 120
  if [[ "$migrate" -eq 1 ]]; then deploy_migrate_path "$path"; fi
  deploy_optimize_path "$path"
  local app; app="$(site_runtime_app_service "$path")"; deploy_compose "$path" exec -T "$app" php artisan queue:restart >/dev/null 2>&1 || true
  site_runtime_health "$site"; inventory_sync "$site" --name="$site" --path="$path"; success "Update Site hoàn tất: $site"
}

site_ops_env_keys() { local file="$1"; [[ -f "$file" ]] || return 0; sed -n -E 's/^([A-Za-z_][A-Za-z0-9_]*)=.*/\1/p' "$file" | sort -u; }
site_ops_env_value() { local file="$1" key="$2"; awk -v key="$key" 'index($0,key "=")==1 {print substr($0,length(key)+2); found=1; exit} END {if (!found) exit 1}' "$file"; }
site_ops_env_diff_keys() {
  local old="$1" new="$2" key old_value new_value
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    old_value="$(site_ops_env_value "$old" "$key" 2>/dev/null || true)"
    new_value="$(site_ops_env_value "$new" "$key" 2>/dev/null || true)"
    if ! grep -qE "^${key}=" "$old" 2>/dev/null || ! grep -qE "^${key}=" "$new" 2>/dev/null || [[ "$old_value" != "$new_value" ]]; then printf '%s\n' "$key"; fi
  done < <(cat <(site_ops_env_keys "$old") <(site_ops_env_keys "$new") | sort -u)
}

site_ops_env_apply() {
  require_root
  local site="${1:-}" source_file="${2:-}"; shift 2 || true
  [[ -n "$site" && -f "$source_file" ]] || die "USAGE: platform site env <site> <env-file> [--dry-run] [--yes]"
  local dry=0 yes=0 arg; for arg in "$@"; do case "$arg" in --dry-run) dry=1;; --yes) yes=1;; *) die "Option không hợp lệ: $arg";; esac; done
  local path env backup keys compose_sensitive=0; path="$(site_runtime_path "$site")"; env="$path/.env"; [[ -f "$env" ]] || die "Site thiếu .env: $path"
  backup="$(mktemp)"; cp -p "$env" "$backup"; keys="$(site_ops_env_diff_keys "$env" "$source_file")"
  grep -Eq '^(APP_|DB_|REDIS_|CACHE_|SESSION_|QUEUE_|BROADCAST_|VITE_|HTTP_PORT|SOCKET_PORT|COMPOSE_)' <<<"$keys" && compose_sensitive=1 || true
  echo "Changed/added/removed keys (values redacted):"; if [[ -n "$keys" ]]; then printf '%s\n' "$keys" | sed 's/^/  - /'; else echo "  (none)"; fi
  echo "Runtime reconcile required: $compose_sensitive"; [[ "$dry" -eq 0 ]] || { rm -f "$backup"; echo "[DRY-RUN] .env unchanged."; return 0; }
  [[ "$yes" -eq 1 ]] || site_confirm "Apply .env update?" || { rm -f "$backup"; die "Đã hủy."; }
  cp "$source_file" "$env"; site_provision_apply_env_permissions "$env"
  if [[ "$compose_sensitive" -eq 1 ]]; then deploy_compose "$path" up -d --no-build --remove-orphans; fi
  local app; app="$(site_runtime_app_service "$path")"; deploy_compose "$path" exec -T "$app" php artisan config:clear; deploy_compose "$path" exec -T "$app" php artisan config:cache
  deploy_compose "$path" exec -T "$app" php artisan queue:restart >/dev/null 2>&1 || true
  if ! site_runtime_health "$site"; then cp "$backup" "$env"; site_provision_apply_env_permissions "$env"; rm -f "$backup"; die "Health fail; .env đã được khôi phục từ checkpoint."; fi
  rm -f "$backup"; success "Update .env hoàn tất: $site"
}

site_ops_diagnostics() {
  local site="${1:-}" path; [[ -n "$site" ]] || die "USAGE: platform site diagnostics <site>"; path="$(site_runtime_path "$site")"
  site_runtime_status "$site"; echo; echo "----- GIT -----"; git -C "$path" status -sb || true; git -C "$path" log -1 --oneline || true
  echo; echo "----- RUNTIME-MANAGED COMPOSE FILES -----"; site_ops_runtime_config_files "$site" "$path" | sed "s#^$path/##" | sed 's/^/  - /' || true
  echo; echo "----- LARAVEL -----"; local app; app="$(site_runtime_app_service "$path" 2>/dev/null || true)"; [[ -n "$app" ]] && deploy_compose "$path" exec -T "$app" php artisan about --only=environment 2>/dev/null || true
  echo; echo "----- RECENT LOGS -----"; deploy_compose "$path" logs --tail=80 2>/dev/null || true
}

site_ops_cleanup() {
  local site="${1:-}"; shift || true; [[ -n "$site" ]] || die "USAGE: platform site cleanup <site> [--apply] [--yes]"
  local apply=0 yes=0 arg path log_bytes; for arg in "$@"; do case "$arg" in --apply) apply=1;; --yes) yes=1;; *) die "Option không hợp lệ: $arg";; esac; done
  path="$(site_runtime_path "$site")"; log_bytes="$(du -sb "$path/storage/logs" 2>/dev/null | awk '{print $1}' || echo 0)"
  echo "Cleanup scope: site-local Laravel logs/cache only"; echo "Laravel log bytes: ${log_bytes:-0}"
  echo "Docker image/build-cache cleanup: HOST-WIDE and intentionally NOT automatic here."; echo "Docker volumes: NEVER pruned by this operation."
  [[ "$apply" -eq 1 ]] || { echo "[REPORT-ONLY] Use --apply --yes to rotate Laravel logs and clear application caches."; return 0; }
  require_root; [[ "$yes" -eq 1 ]] || site_confirm "Apply site-local cleanup?" || die "Đã hủy."
  find "$path/storage/logs" -type f -name '*.log' -size +20M -exec sh -c ': > "$1"' _ {} \; 2>/dev/null || true
  local app; app="$(site_runtime_app_service "$path")"; deploy_compose "$path" exec -T "$app" env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
  success "Production cleanup site-local hoàn tất: $site"
}
