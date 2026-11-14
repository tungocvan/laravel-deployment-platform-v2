#!/usr/bin/env bash

# Overrides the base Site menu bootstrap flow after modules/ui/menus/sites.sh is loaded.
# This keeps the destructive replace confirmation isolated from the normal site menu.
ui_flow_bootstrap_repository() {
  local site new_repo replace_existing=0 typed
  site="$(ui_select_site "Chọn site cần KHỞI TẠO / THAY KHO ĐÍCH")" || return 0

  ui_section "KHỞI TẠO / THAY MAIN KHO ĐÍCH TỪ KHO CŨ"
  echo "Quy trình an toàn:"
  echo "  - Đọc source chuẩn trực tiếp từ kho cũ/main"
  echo "  - Kho đích trống: tạo main như hiện tại"
  echo "  - Kho đích đã có main: chỉ replace khi người dùng xác nhận rõ ràng"
  echo "  - Replace tạo backup ref tạm và dùng force-with-lease đúng SHA đã kiểm tra"
  echo "  - Verify SHA + tree 100% trước khi đổi origin site"
  echo "  - Branch/tag khác của kho đích KHÔNG bị xóa"
  echo "  - HEAD/worktree/deploy/database/container của site được giữ nguyên"
  echo
  ui_run site show "$site"
  echo

  new_repo="$(ui_prompt "Repository mới (owner/name hoặc git@github.com:owner/name.git)")"
  [[ -n "$new_repo" ]] || { echo "[ERROR] Repository đích bắt buộc."; ui_pause; return; }

  echo
  echo "[INFO] Bootstrap chỉ tạo và chuẩn bị repository mới; KHÔNG đổi origin của site."
  echo "[INFO] Sau khi bootstrap PASS, quay lại chức năng 21 để chuyển origin."
  ui_section "BOOTSTRAP VERIFY / DRY-RUN"
  ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --prepare-only --dry-run || {
    echo "[ERROR] Bootstrap dry-run thất bại; site chưa bị thay đổi."
    ui_pause
    return
  }

  echo
  echo "CẢNH BÁO: Bước tiếp theo có thể TẠO repository GitHub mới và PUSH source/main."
  echo "Không thay đổi origin, Inventory, HEAD, worktree, deploy, database hay container."
  if ui_confirm_execute "BOOTSTRAP NEW REPOSITORY: $site → $new_repo"; then
    ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --prepare-only --yes
    echo "[INFO] Nếu bootstrap thành công, dùng chức năng 21 để đổi repository của website."
  fi

  ui_pause
}
