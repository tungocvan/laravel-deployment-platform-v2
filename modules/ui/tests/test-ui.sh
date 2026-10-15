#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"

for f in \
  "$ROOT/modules/ui/lib/ui.sh" \
  "$ROOT/modules/ui/menus/main.sh" \
  "$ROOT/modules/ui/menus/site-operations-v2.sh" \
  "$ROOT/modules/ui/menus/infrastructure.sh" \
  "$ROOT/modules/ui/menus/backup.sh" \
  "$ROOT/modules/ui/menus/sites.sh" \
  "$ROOT/modules/ui/menus/deploy.sh" \
  "$ROOT/modules/ui/menus/doctor.sh" \
  "$ROOT/modules/ui/menus/packages.sh" \
  "$ROOT/modules/ui/flows/bootstrap-repository.sh" \
  "$ROOT/modules/ui/flows/repository-access.sh" \
  "$ROOT/modules/ui/commands/menu.sh"
do
  [[ -f "$f" ]] || { echo "[ERROR] Missing: $f"; exit 1; }
  bash -n "$f"
done

grep -q '^ui_ssl_wizard()' "$ROOT/modules/ui/lib/ui.sh"
grep -q '^ui_ssl_wizard_issue_loop()' "$ROOT/modules/ui/lib/ui.sh"
grep -q '^ui_inventory_site_by_domain_json()' "$ROOT/modules/ui/lib/ui.sh"
grep -q 'Hướng dẫn cấp chứng chỉ SSL' "$ROOT/modules/ui/menus/infrastructure.sh"
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

# Repository access workflow: menu 18 probes read/write/delete without touching
# main, reuses an existing owner SSH alias before creating a new credential,
# can generate a repository-specific key, and never prints the private key.
grep -q '18) Kiểm tra quyền repository / SSH key' "$ROOT/modules/ui/menus/sites.sh"
grep -q '18) ui_flow_repository_access' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'source "$PLATFORM_HOME/modules/ui/flows/repository-access.sh"' "$ROOT/modules/ui/commands/menu.sh"
grep -q '^ui_flow_repository_access()' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q '^ui_repo_access_existing_owner_alias()' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q '"github-$owner" "github-$owner-$name"' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'Phát hiện SSH alias đã có cho owner' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'Không cần tạo SSH key mới' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'refs/platform/write-probe/access-' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'github_${owner}_${name}_ed25519' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'Private key: .*KHÔNG hiển thị' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'cat "$key_file.pub"' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'Allow write access' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'Repository URL mới' "$ROOT/modules/ui/flows/repository-access.sh"
! grep -q 'cat "$key_file"' "$ROOT/modules/ui/flows/repository-access.sh"
grep -q 'Kiểm tra quyền GitHub / tạo SSH key riêng' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Không bao giờ chia sẻ private SSH key' "$ROOT/modules/ui/menus/main.sh"

# Professional navigation contract: top-level items explain their contents and
# an operator guide must be reachable directly from the first screen.
grep -q '^ui_quick_guide()' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Sites Management' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Deploy & Runtime' "$ROOT/modules/ui/menus/main.sh"
grep -q 'Hướng dẫn sử dụng / Chọn đúng chức năng' "$ROOT/modules/ui/menus/main.sh"
grep -q 'source "$PLATFORM_HOME/modules/ui/menus/main.sh"' "$ROOT/modules/ui/commands/menu.sh"

# Deploy menu must make the fast .env/config workflow discoverable without
# requiring operators to know that it is implemented by deploy optimize.
grep -q 'Backend / Laravel Runtime (Migrate, Optimize/Reload .env, Health)' "$ROOT/modules/ui/menus/deploy.sh"
grep -q 'Optimize / Reload .env' "$ROOT/modules/ui/menus/deploy.sh"
grep -q 'Health Check — Services + Laravel Boot + Public Storage + Application HTTP' "$ROOT/modules/ui/menus/deploy.sh"
grep -q 'Full Deploy — build images + Docker up + migrate + optimize' "$ROOT/modules/ui/menus/deploy.sh"

grep -q 'REPOSITORY MANAGEMENT' "$ROOT/modules/ui/menus/sites.sh"
grep -q 'INFRASTRUCTURE — SSL CERTIFICATES / NGINX ROUTING' "$ROOT/modules/ui/menus/infrastructure.sh"
grep -q 'DOCTOR & DOMAIN DIAGNOSTICS' "$ROOT/modules/ui/menus/doctor.sh"
grep -q 'PACKAGES — INVENTORY / VERIFY / HISTORY' "$ROOT/modules/ui/menus/packages.sh"

# Platform 2.1 navigation: all nine categories must have Vietnamese help
# and site actions must reuse the existing guarded operation dispatcher.
for title in \
  'Dashboard & Site Overview' 'Sites Management' 'Deploy & Runtime' \
  'Backup & Recovery' 'Monitoring & Diagnostics' \
  'Infrastructure — SSL & Nginx' 'Maintenance & Safety' \
  'Repository & SSH' 'Packages & Help & Upgrade Menu'
do
  grep -Fq "$title" "$ROOT/modules/ui/menus/main.sh"
done
grep -Fq 'Xem danh sách, thông tin và trạng thái các website' "$ROOT/modules/ui/menus/main.sh"
grep -Fq 'Dọn dẹp, lưu trữ hoặc xóa site với bước xác nhận an toàn' "$ROOT/modules/ui/menus/main.sh"
grep -Fq 'Quản lý gói, xem hướng dẫn và lấy prompt nâng cấp Platform 2.1' "$ROOT/modules/ui/menus/main.sh"
grep -q '^ui_site_operation_dispatch()' "$ROOT/modules/ui/menus/site-operations-v2.sh"
grep -q '^ui_site_operations_group()' "$ROOT/modules/ui/menus/site-operations-v2.sh"
grep -Fq 'ui_site_operation_dispatch "$c"' "$ROOT/modules/ui/menus/site-operations-v2.sh"
grep -Fq 'ui_site_operation_dispatch "$choice"' "$ROOT/modules/ui/menus/site-operations-v2.sh" || grep -Fq 'ui_site_operation_dispatch 25' "$ROOT/modules/ui/menus/main.sh"

# Checkpoint 60: each legacy submenu now includes a Vietnamese explanation.
for pair in \
  'modules/ui/menus/backup.sh|Khôi phục website hiện tại — CẢNH BÁO' \
  'modules/ui/menus/doctor.sh|Kiểm tra tên miền và định danh website' \
  'modules/ui/menus/deploy.sh|Chạy migration cơ sở dữ liệu — CẢNH BÁO' \
  'modules/ui/menus/infrastructure.sh|Kiểm tra xung đột Nginx' \
  'modules/ui/menus/packages.sh|Kiểm tra tính toàn vẹn gói' \
  'modules/ui/menus/site-operations-v2.sh|Dọn dẹp Docker trên toàn VPS — CẢNH BÁO'
do
  file="${pair%%|*}"
  phrase="${pair#*|}"
  grep -Fq "$phrase" "$ROOT/$file"
done
grep -Fq 'ui_site_operation_dispatch "$c"' "$ROOT/modules/ui/menus/site-operations-v2.sh"
! grep -Fq '|| continue; cmd=' "$ROOT/modules/ui/menus/site-operations-v2.sh"
! grep -Fq '  LARAVEL DEPLOYMENT PLATFORM v2.1' "$ROOT/modules/ui/menus/main.sh"
grep -Fq 'Repository & SSH → Update repository' "$ROOT/modules/ui/menus/main.sh"
# Read-only upgrade prompt must be reachable from menu 9 and must not execute commands.
grep -q '^ui_upgrade_prompt_guide()' "$ROOT/modules/ui/menus/main.sh"
grep -Fq '3) Prompt nâng cấp Platform 2.1 (chỉ đọc)' "$ROOT/modules/ui/menus/main.sh"
grep -Fq '3) ui_upgrade_prompt_guide ;;' "$ROOT/modules/ui/menus/main.sh"
grep -Fq 'Đọc INFORMATION.md và audit read-only branch main mới nhất' "$ROOT/modules/ui/menus/main.sh"
grep -Fq 'không tự merge' "$ROOT/modules/ui/menus/main.sh"
echo "[OK] Platform 2.1 Vietnamese submenu descriptions and upgrade prompt"
