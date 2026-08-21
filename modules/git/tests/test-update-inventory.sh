#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"
UPDATE="$ROOT/modules/git/commands/update.sh"

grep -q 'inventory_sync "$site"' "$UPDATE"
grep -q 'Inventory synced' "$UPDATE"

merge_line="$(grep -n 'merge --ff-only' "$UPDATE" | head -n1 | cut -d: -f1)"
verify_line="$(grep -n 'platform_git_verify "$path"' "$UPDATE" | tail -n1 | cut -d: -f1)"
sync_line="$(grep -n 'inventory_sync "$site"' "$UPDATE" | tail -n1 | cut -d: -f1)"

[[ -n "$merge_line" && -n "$verify_line" && -n "$sync_line" ]]
(( sync_line > merge_line ))
(( sync_line > verify_line ))

bash -n "$UPDATE"
echo "[OK] Git update Inventory sync contract"
