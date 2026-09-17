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
grep -q 'Changed/added/removed keys' "$ROOT/modules/site/lib/operations.sh"
grep -q 'HOST-WIDE' "$ROOT/modules/site/lib/operations.sh"
grep -q 'NEVER pruned' "$ROOT/modules/site/lib/operations.sh"
grep -q 'migrate:fresh|db:wipe' "$ROOT/modules/site/lib/runtime.sh"
! grep -Eq 'git clean -fd|reset --hard|volume prune|system prune|down -v' "$ROOT/modules/site/lib/operations.sh"
echo "PASS production-site-operations-v2 contract"
