#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
files=(
  "$ROOT/modules/site/lib/runtime.sh"
  "$ROOT/modules/site/lib/deploy-readiness.sh"
  "$ROOT/modules/site/lib/operations.sh"
  "$ROOT/modules/site/lib/reconcile.sh"
  "$ROOT/modules/site/lib/env-management.sh"
  "$ROOT/modules/site/commands/update.sh"
  "$ROOT/modules/site/commands/env.sh"
  "$ROOT/modules/site/commands/diagnostics.sh"
  "$ROOT/modules/site/commands/artisan.sh"
  "$ROOT/modules/site/commands/runtime.sh"
  "$ROOT/modules/site/commands/cleanup.sh"
  "$ROOT/modules/ui/menus/site-operations-v2.sh"
)
for f in "${files[@]}"; do bash -n "$f"; done

ops="$ROOT/modules/site/lib/operations.sh"; menu="$ROOT/modules/ui/menus/site-operations-v2.sh"; readiness="$ROOT/modules/site/lib/deploy-readiness.sh"; update_cmd="$ROOT/modules/site/commands/update.sh"; reconcile="$ROOT/modules/site/lib/reconcile.sh"; env_cmd="$ROOT/modules/site/commands/env.sh"; env_management="$ROOT/modules/site/lib/env-management.sh"
grep -q 'config --services' "$ROOT/modules/site/lib/runtime.sh"
grep -q 'merge --ff-only' "$ops"
grep -q 'com.docker.compose.project.config_files' "$ops"
grep -q 'ACTIVE RUNTIME-MANAGED OVERLAYS' "$ops"
grep -q 'STALE EMPTY PLATFORM OVERLAYS' "$ops"
grep -q 'UNKNOWN / NON-EMPTY UNTRACKED (BLOCKING)' "$ops"
grep -q 'MIGRATION-REQUIRED' "$ops"
grep -q 'return 3' "$ops"
grep -q 'ui_flow_production_update' "$menu"
grep -q 'site update.*--migrate --yes' "$menu"
grep -q 'Changed/added/removed keys (values redacted)' "$ops"
grep -q 'HOST-WIDE' "$ops"
grep -q 'NEVER pruned' "$ops"
grep -q 'migrate:fresh|db:wipe' "$ROOT/modules/site/lib/runtime.sh"
! grep -Eq 'git clean -fd|reset --hard|volume prune|system prune|down -v' "$ops"

grep -q 'DB::connection()->getPdo()' "$readiness"
grep -q 'Console\\Kernel::class.*bootstrap' "$readiness"
grep -q "grep -Eqi 'Up|healthy|running'" "$readiness"
! grep -q 'getenv("DB_' "$readiness"

# Reconcile is explicit, source-neutral and migration-neutral.
grep -q 'modules/site/lib/reconcile.sh' "$update_cmd"
grep -q 'site_ops_reconcile' "$update_cmd"
grep -q -- '--reconcile' "$update_cmd"
grep -q 'PRODUCTION RUNTIME RECONCILE PLAN' "$reconcile"
grep -q 'Git mutation  : NO' "$reconcile"
grep -q 'Docker build  : NO' "$reconcile"
grep -q 'Migration     : NO' "$reconcile"
grep -q 'up -d --no-build --remove-orphans' "$reconcile"
grep -q 'deploy_wait_database' "$reconcile"
grep -q 'deploy_optimize_path' "$reconcile"
grep -q 'queue:restart' "$reconcile"
grep -q 'site_runtime_health' "$reconcile"
grep -q 'inventory_sync' "$reconcile"
grep -q -- '--migrate không được phép cùng --reconcile' "$reconcile"
! grep -Eq 'git .*fetch|git .*merge|deploy_compose .* build|migrate --force|backup_create' "$reconcile"

# UI exposes an explicit recovery path and always previews before apply.
grep -q 'ui_flow_production_reconcile' "$menu"
grep -q 'Reconcile / Resume Runtime' "$menu"
grep -q 'Không Git mutation, không Docker build và không database migration' "$menu"
grep -q 'site update.*--reconcile --dry-run.*|| rc=' "$menu"
grep -q 'RECONCILE / RESUME RUNTIME' "$menu"
grep -q 'site update.*--reconcile --yes' "$menu"
grep -q '25) ui_flow_production_reconcile' "$menu"

# Site-aware env UX resolves the selected site's .env and edits only a staging copy.
grep -q 'ui_flow_production_env' "$menu"
grep -q 'Manage .env — site-aware staging' "$menu"
grep -q '3) ui_flow_production_env' "$menu"
grep -q 'site env.*--keys' "$menu"
grep -q 'site env.*--edit' "$menu"
grep -q 'Đường dẫn file .env cần import' "$menu"
grep -q 'modules/site/lib/env-management.sh' "$env_cmd"
grep -q -- '--keys) site_ops_env_list_keys' "$env_cmd"
grep -q -- '--edit) site_ops_env_edit' "$env_cmd"
grep -q 'staged="$(mktemp)"' "$env_management"
grep -q 'cp -p "$env" "$staged"' "$env_management"
grep -q 'site_ops_env_apply "$site" "$staged" --dry-run' "$env_management"
grep -q 'site_ops_env_apply "$site" "$staged" --yes' "$env_management"
! grep -q 'cat "$env"' "$env_management"

# Functional env comparator: changed values report key names only, never values.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat >"$tmp/old.env" <<'EOF'
APP_ENV=production
DB_PASSWORD=old-super-secret
UNCHANGED=same
REMOVED=gone
EOF
cat >"$tmp/new.env" <<'EOF'
APP_ENV=production
DB_PASSWORD=new-super-secret
UNCHANGED=same
ADDED=new
EOF
# shellcheck disable=SC1090
source "$ops"
diff_keys="$(site_ops_env_diff_keys "$tmp/old.env" "$tmp/new.env")"
grep -qx 'ADDED' <<<"$diff_keys"; grep -qx 'DB_PASSWORD' <<<"$diff_keys"; grep -qx 'REMOVED' <<<"$diff_keys"; ! grep -q 'UNCHANGED' <<<"$diff_keys"; ! grep -q 'old-super-secret\|new-super-secret' <<<"$diff_keys"

mkdir -p "$tmp/site"; touch "$tmp/site/compose.active.yaml" "$tmp/site/random.txt"; runtime_files="$(readlink -f "$tmp/site/compose.active.yaml")"
site_ops_runtime_owned_overlay "$tmp/site" 'compose.active.yaml' "$runtime_files"; ! site_ops_runtime_owned_overlay "$tmp/site" 'random.txt' "$runtime_files"; ! site_ops_runtime_owned_overlay "$tmp/site" 'compose.socket.yaml' "$runtime_files"
printf 'services: {}\n' >"$tmp/site/compose.queue.yaml"; printf '# legacy placeholder\n\nservices: {}   # empty\n' >"$tmp/site/compose.scheduler.yaml"
site_ops_stale_empty_legacy_overlay "$tmp/site" 'compose.queue.yaml' "$runtime_files"; site_ops_stale_empty_legacy_overlay "$tmp/site" 'compose.scheduler.yaml' "$runtime_files"
cat >"$tmp/site/compose.socket.yaml" <<'EOF'
services:
  socket:
    image: example/socket
EOF
! site_ops_stale_empty_legacy_overlay "$tmp/site" 'compose.socket.yaml' "$runtime_files"
printf 'services: {}\n' >"$tmp/site/compose.unknown.yaml"; ! site_ops_stale_empty_legacy_overlay "$tmp/site" 'compose.unknown.yaml' "$runtime_files"
runtime_queue="$(readlink -f "$tmp/site/compose.queue.yaml")"; ! site_ops_stale_empty_legacy_overlay "$tmp/site" 'compose.queue.yaml' "$runtime_queue"

echo "PASS production-site-operations-v2 contract"
