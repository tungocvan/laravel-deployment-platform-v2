#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"

for f in \
  "$ROOT/modules/ui/lib/ui.sh" \
  "$ROOT/modules/ui/menus/infrastructure.sh" \
  "$ROOT/modules/ui/menus/backup.sh" \
  "$ROOT/modules/ui/menus/sites.sh" \
  "$ROOT/modules/ui/commands/menu.sh"
do
  [[ -f "$f" ]] || { echo "[ERROR] Missing: $f"; exit 1; }
  bash -n "$f"
done

grep -q '^ui_ssl_wizard()' "$ROOT/modules/ui/lib/ui.sh"
grep -q '^ui_ssl_wizard_issue_loop()' "$ROOT/modules/ui/lib/ui.sh"
grep -q '^ui_inventory_site_by_domain_json()' "$ROOT/modules/ui/lib/ui.sh"
grep -q 'SSL Wizard' "$ROOT/modules/ui/menus/infrastructure.sh"
grep -q 'ssl issue "$domain"' "$ROOT/modules/ui/lib/ui.sh"
grep -q 'ssl verify "$domain"' "$ROOT/modules/ui/lib/ui.sh"
grep -q 'git@github.com:tungocvan/laravel-shop.git' "$ROOT/modules/ui/menus/sites.sh"
! grep -q 'git@github.com:vhdtshop-ux/source-laravel-12.git' "$ROOT/modules/ui/menus/sites.sh"

grep -q 'Update kho mới (main phải giống 100%)' "$ROOT/modules/ui/menus/sites.sh"
grep -q '^ui_flow_update_repository()' "$ROOT/modules/ui/menus/sites.sh"
grep -q -- '--require-identical-main --dry-run' "$ROOT/modules/ui/menus/sites.sh"
grep -q -- '--require-identical-main --yes' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'Không đủ điều kiện thay đổi repository' "$ROOT/modules/ui/menus/sites.sh"

echo "[OK] Interactive UI dev.5 + strict repository update flow"
