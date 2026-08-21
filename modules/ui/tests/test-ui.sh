#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"

for f in \
  "$ROOT/modules/ui/lib/ui.sh" \
  "$ROOT/modules/ui/menus/main.sh" \
  "$ROOT/modules/ui/menus/infrastructure.sh" \
  "$ROOT/modules/ui/menus/backup.sh" \
  "$ROOT/modules/ui/menus/sites.sh" \
  "$ROOT/modules/ui/menus/deploy.sh" \
  "$ROOT/modules/ui/menus/doctor.sh" \
  "$ROOT/modules/ui/menus/packages.sh" \
  "$ROOT/modules/ui/flows/bootstrap-repository.sh" \
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

grep -q 'Update kho mới (main cùng dòng source)' "$ROOT/modules/ui/menus/sites.sh"
grep -q '^ui_flow_update_repository()' "$ROOT/modules/ui/menus/sites.sh"
grep -q -- '--require-compatible-main --dry-run' "$ROOT/modules/ui/menus/sites.sh"
grep -q -- '--require-compatible-main --yes' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'Kho mới không cùng dòng source main' "$ROOT/modules/ui/menus/sites.sh"

grep -q 'Khởi tạo kho mới trống từ kho cũ' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'source "$PLATFORM_HOME/modules/ui/flows/bootstrap-repository.sh"' "$ROOT/modules/ui/commands/menu.sh"
grep -q '^ui_flow_bootstrap_repository()' "$ROOT/modules/ui/flows/bootstrap-repository.sh"
grep -q -- '--replace-existing --dry-run' "$ROOT/modules/ui/flows/bootstrap-repository.sh"
grep -q -- '--replace-existing --yes' "$ROOT/modules/ui/flows/bootstrap-repository.sh"
grep -q 'Cho phép kiểm tra lại với chế độ REPLACE target/main' "$ROOT/modules/ui/flows/bootstrap-repository.sh"
grep -q 'Nhập chính xác URL repo đích' "$ROOT/modules/ui/flows/bootstrap-repository.sh"
grep -q 'Branch/tag khác của kho đích KHÔNG bị xóa' "$ROOT/modules/ui/flows/bootstrap-repository.sh"
grep -q 'force-with-lease' "$ROOT/modules/ui/flows/bootstrap-repository.sh"

grep -q '17) Đồng bộ 2 kho Git' "$ROOT/modules/ui/menus/sites.sh"
grep -q '^ui_flow_sync_repositories()' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'git sync-repositories.*--dry-run' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'git sync-repositories.*--yes' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'Target ahead hoặc diverged: BLOCK' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'Không force-push, không tự merge, không sync ngược' "$ROOT/modules/ui/menus/sites.sh"

# Professional navigation contract: top-level items explain their contents and
# an operator guide must be reachable directly from the first screen.
grep -q '^ui_quick_guide()' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Sites & Repository' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Deploy & Runtime' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Hướng dẫn sử dụng / Chọn đúng chức năng' "$ROOT/modules/ui/menus/main.sh"
grep -q 'source "$PLATFORM_HOME/modules/ui/menus/main.sh"' "$ROOT/modules/ui/commands/menu.sh"

# Deploy menu must make the fast .env/config workflow discoverable without
# requiring operators to know that it is implemented by deploy optimize.
grep -q 'Backend / Laravel Runtime (Migrate, Optimize/Reload .env, Health)' "$ROOT/modules/ui/menus/deploy.sh"
grep -q 'Optimize / Reload .env' "$ROOT/modules/ui/menus/deploy.sh"
grep -q 'Health Check — Services + Laravel Boot + Application HTTP' "$ROOT/modules/ui/menus/deploy.sh"
grep -q 'Full Deploy — build images + Docker up + migrate + optimize' "$ROOT/modules/ui/menus/deploy.sh"

grep -q 'REPOSITORY MANAGEMENT' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'INFRASTRUCTURE — SSL CERTIFICATES / NGINX ROUTING' "$ROOT/modules/ui/menus/infrastructure.sh"
grep -q 'DOCTOR & DOMAIN DIAGNOSTICS' "$ROOT/modules/ui/menus/doctor.sh"
grep -q 'PACKAGES — INVENTORY / VERIFY / HISTORY' "$ROOT/modules/ui/menus/packages.sh"

echo "[OK] Interactive UI dev.6 + descriptive operations console + repository/deploy guidance"
