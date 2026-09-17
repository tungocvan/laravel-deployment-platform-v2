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

grep -q 'config --services' "$ROOT/modules/site/lib/runtime.sh"
grep -q 'merge --ff-only' "$ROOT/modules/site/lib/operations.sh"
grep -q 'UPDATE SITE — BLOCKED: WORKING TREE NOT CLEAN' "$ROOT/modules/site/lib/operations.sh"
grep -q 'TRACKED MODIFIED / STAGED' "$ROOT/modules/site/lib/operations.sh"
grep -q 'UNTRACKED:' "$ROOT/modules/site/lib/operations.sh"
grep -q 'site-local/runtime-managed' "$ROOT/modules/site/lib/operations.sh"
grep -q 'Không tự git add, git clean hoặc xóa' "$ROOT/modules/site/lib/operations.sh"
grep -q 'Changed/added/removed keys (values redacted)' "$ROOT/modules/site/lib/operations.sh"
grep -q 'old_value.*new_value' "$ROOT/modules/site/lib/operations.sh"
grep -q 'old_value.*!=.*new_value' "$ROOT/modules/site/lib/operations.sh"
grep -q 'HOST-WIDE' "$ROOT/modules/site/lib/operations.sh"
grep -q 'NEVER pruned' "$ROOT/modules/site/lib/operations.sh"
grep -q 'migrate:fresh|db:wipe' "$ROOT/modules/site/lib/runtime.sh"
! grep -Eq 'git clean -fd|reset --hard|volume prune|system prune|down -v' "$ROOT/modules/site/lib/operations.sh"

# Functional env comparator: changed values must report key names only, never values.
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
source "$ROOT/modules/site/lib/operations.sh"
diff_keys="$(site_ops_env_diff_keys "$tmp/old.env" "$tmp/new.env")"
grep -qx 'ADDED' <<<"$diff_keys"
grep -qx 'DB_PASSWORD' <<<"$diff_keys"
grep -qx 'REMOVED' <<<"$diff_keys"
! grep -q 'UNCHANGED' <<<"$diff_keys"
! grep -q 'old-super-secret\|new-super-secret' <<<"$diff_keys"

echo "PASS production-site-operations-v2 contract"
