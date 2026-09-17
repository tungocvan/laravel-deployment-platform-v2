#!/usr/bin/env bash

# Resume/reconcile a production site after a partial update. This operation is
# deliberately source-neutral: it never fetches, merges, builds or migrates.
site_ops_reconcile() {
  require_root

  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform-v2 site update <site> --reconcile [--dry-run] [--yes]"

  local dry=0 yes=0 arg path branch commit app
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry=1 ;;
      --yes) yes=1 ;;
      --reconcile) ;;
      --migrate) die "--migrate không được phép cùng --reconcile. Reconcile không chạy migration." ;;
      *) die "Option không hợp lệ cho reconcile: $arg" ;;
    esac
  done

  path="$(site_runtime_path "$site")"
  platform_git_trust "$path"
  if site_ops_dirty_report "$site" "$path"; then return 2; fi

  branch="$(git -C "$path" branch --show-current)"
  [[ -n "$branch" ]] || die "Detached HEAD. Reconcile bị BLOCK."
  commit="$(git -C "$path" rev-parse HEAD)"
  app="$(site_runtime_app_service "$path")"
  [[ -n "$app" ]] || die "Không xác định được application service."

  echo "========================================================="
  echo "PRODUCTION RUNTIME RECONCILE PLAN"
  echo "========================================================="
  echo "Site          : $site"
  echo "Path          : $path"
  echo "Branch        : $branch"
  echo "Commit        : $commit"
  echo "App service   : $app"
  echo "Git mutation  : NO"
  echo "Docker build  : NO"
  echo "Migration     : NO"
  echo "Steps         : preflight -> compose reconcile -> DB readiness -> optimize -> queue restart -> health -> inventory sync"

  if [[ "$dry" -eq 1 ]]; then
    echo "[DRY-RUN] Không thay đổi source/runtime."
    return 0
  fi

  [[ "$yes" -eq 1 ]] || site_confirm "Reconcile production runtime: $site ?" || die "Đã hủy."

  echo "[RECONCILE 1/7] Ensure Docker project identity + preflight"
  deploy_ensure_identity_path "$site" "$path" >/dev/null
  deploy_preflight "$path"

  echo "[RECONCILE 2/7] Compose reconcile (no build)"
  deploy_compose "$path" up -d --no-build --remove-orphans

  echo "[RECONCILE 3/7] Laravel database readiness"
  deploy_wait_database "$path" 120

  echo "[RECONCILE 4/7] Laravel optimize"
  deploy_optimize_path "$path"

  echo "[RECONCILE 5/7] Queue restart"
  deploy_compose "$path" exec -T "$app" php artisan queue:restart

  echo "[RECONCILE 6/7] Runtime health"
  site_runtime_health "$site"

  echo "[RECONCILE 7/7] Inventory sync"
  inventory_sync "$site" --name="$site" --path="$path"

  success "Production runtime reconcile hoàn tất: $site"
}
