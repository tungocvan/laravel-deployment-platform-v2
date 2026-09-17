#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
files=(
  "$ROOT/modules/site/lib/runtime.sh"
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

ops="$ROOT/modules/site/lib/operations.sh"
grep -q 'config --services' "$ROOT/modules/site/lib/runtime.sh"
grep -q 'merge --ff-only' "$ops"
grep -q 'com.docker.compose.project.config_files' "$ops"
grep -q 'com.docker.compose.project=' "$ops"
grep -q 'RUNTIME-MANAGED OVERLAYS' "$ops"
grep -q 'verified from live Docker Compose labels' "$ops"
grep -q 'UNTRACKED (NOT VERIFIED AS RUNTIME-MANAGED)' "$ops"
grep -q 'Changed/added/removed keys (values redacted)' "$ops"
grep -q 'old_value.*new_value' "$ops"
grep -q 'old_value.*!=.*new_value' "$ops"
grep -q 'HOST-WIDE' "$ops"
grep -q 'NEVER pruned' "$ops"
grep -q 'migrate:fresh|db:wipe' "$ROOT/modules/site/lib/runtime.sh"
! grep -Eq 'git clean -fd|reset --hard|volume prune|system prune|down -v' "$ops"

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
grep -qx 'ADDED' <<<"$diff_keys"
grep -qx 'DB_PASSWORD' <<<"$diff_keys"
grep -qx 'REMOVED' <<<"$diff_keys"
! grep -q 'UNCHANGED' <<<"$diff_keys"
! grep -q 'old-super-secret\|new-super-secret' <<<"$diff_keys"

# Ownership matcher is exact-path and Compose-overlay-only; no wildcard trust.
mkdir -p "$tmp/site"
touch "$tmp/site/compose.queue.yaml" "$tmp/site/random.txt"
runtime_files="$(readlink -f "$tmp/site/compose.queue.yaml")"
site_ops_runtime_owned_overlay "$tmp/site" 'compose.queue.yaml' "$runtime_files"
! site_ops_runtime_owned_overlay "$tmp/site" 'random.txt' "$runtime_files"
! site_ops_runtime_owned_overlay "$tmp/site" 'compose.socket.yaml' "$runtime_files"

echo "PASS production-site-operations-v2 contract"
