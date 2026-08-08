#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"

for f in \
  "$ROOT/modules/ui/lib/ui.sh" \
  "$ROOT/modules/ui/menus/infrastructure.sh" \
  "$ROOT/modules/ui/menus/backup.sh" \
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

echo "[OK] Interactive UI dev.5"
