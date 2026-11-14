#!/usr/bin/env bash

# Overrides the base Site menu bootstrap flow after modules/ui/menus/sites.sh is loaded.
# Menu 22 creates a new private repository; menu 21 separately migrates origin.
ui_flow_bootstrap_repository() {
  local site new_repo
  site="$(ui_select_site "Chọn site cần TẠO REPOSITORY MỚI")" || return 0

  ui_section "TẠO REPOSITORY GITHUB MỚI — PREPARE ONLY"
  echo "Quy trình an toàn:"
  echo "  - Chỉ hỗ trợ repository mới thuộc owner tungocvan"
  echo "  - Kiểm tra source/main và lịch sử Git của website"
  echo "  - Tạo repository GitHub PRIVATE mới, từ chối nếu đã tồn tại"
  echo "  - Push source/main -> repository mới/main, không force-push"
  echo "  - Verify SHA của main sau khi push"
  echo "  - KHÔNG đổi origin hay Inventory; chức năng 21 xử lý riêng"
  echo "  - Không deploy, không thay đổi database/container"
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
