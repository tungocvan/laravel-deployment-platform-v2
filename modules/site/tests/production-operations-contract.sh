#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
files=(
  "$ROOT/modules/site/lib/runtime.sh"
  "$ROOT/modules/site/lib/deploy-readiness.sh"
  "$ROOT/modules/site/lib/operations.sh"
  "$ROOT/modules/site/commands/update.sh"
  "$ROOT/modules/site/commands/env.sh"
  "$ROOT/modules/site/commands/diagnostics.sh"
  "$ROOT/modules/site/commands/artisan.sh"
  "$ROOT/modules/site/commands/runtime.sh"
  "$ROOT/modules/site/commands/cleanup.sh"
  "$ROOT/modules/ui/menus/site-operations-v2.sh"
)
for f in "${files[@]}"; do bash -n "$f"; done

ops="$ROOT/modules/site/lib/operations.sh"; menu="$ROOT/modules/ui/menus/site-operations-v2.sh"; readiness="$ROOT/modules/site/lib/deploy-readiness.sh"; update_cmd="$ROOT/modules/site/commands/update.sh"
grep -q 'config --services' "$ROOT/modules/site/lib/runtime.sh"
grep -q 'merge --ff-only' "$ops"
grep -q 'com.docker.compose.project.config_files' "$ops"
grep -q 'com.docker.compose.project=' "$ops"
grep -q 'ACTIVE RUNTIME-MANAGED OVERLAYS' "$ops"
grep -q 'STALE EMPTY PLATFORM OVERLAYS' "$ops"
grep -q 'UNKNOWN / NON-EMPTY UNTRACKED (BLOCKING)' "$ops"
grep -q 'KHÔNG bị tự động xóa' "$ops"
grep -q 'MIGRATION-REQUIRED' "$ops"
grep -q 'return 3' "$ops"
grep -q 'ui_flow_production_update' "$menu"
grep -q 'ui_run_sudo site update.*--dry-run.*|| rc=' "$menu"
grep -q 'Cho phép chạy migration' "$menu"
grep -q 'site update.*--migrate --yes' "$menu"
grep -q 'verified backup checkpoint' "$menu"
grep -q 'Changed/added/removed keys (values redacted)' "$ops"
grep -q 'old_value.*new_value' "$ops"
grep -q 'old_value.*!=.*new_value' "$ops"
grep -q 'HOST-WIDE' "$ops"
grep -q 'NEVER pruned' "$ops"
grep -q 'migrate:fresh|db:wipe' "$ROOT/modules/site/lib/runtime.sh"
! grep -Eq 'git clean -fd|reset --hard|volume prune|system prune|down -v' "$ops"

# Production update readiness must use Laravel's resolved configuration, not
# getenv(DB_*), and the scoped override must load after shared deploy/runtime.
grep -q 'DB::connection()->getPdo()' "$readiness"
grep -q 'Console\\Kernel::class.*bootstrap' "$readiness"
grep -q "grep -Eqi 'Up|healthy|running'" "$readiness"
grep -q 'Laravel database connection ready' "$readiness"
! grep -q 'getenv("DB_' "$readiness"
grep -q 'modules/deploy/lib/deploy.sh' "$update_cmd"
grep -q 'modules/site/lib/runtime.sh' "$update_cmd"
grep -q 'modules/site/lib/deploy-readiness.sh' "$update_cmd"
[[ "$(grep -n 'modules/deploy/lib/deploy.sh' "$update_cmd" | cut -d: -f1)" -lt "$(grep -n 'modules/site/lib/deploy-readiness.sh' "$update_cmd" | cut -d: -f1)" ]]
[[ "$(grep -n 'modules/site/lib/runtime.sh' "$update_cmd" | cut -d: -f1)" -lt "$(grep -n 'modules/site/lib/deploy-readiness.sh' "$update_cmd" | cut -d: -f1)" ]]

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
