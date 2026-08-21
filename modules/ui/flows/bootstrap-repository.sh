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

  new_repo="$(ui_prompt "Địa chỉ Git repository ĐÍCH")"
  [[ -n "$new_repo" ]] || { echo "[ERROR] Repository đích bắt buộc."; ui_pause; return; }

  ui_section "BOOTSTRAP VERIFY / DRY-RUN"
  if ! ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --dry-run; then
    echo
    echo "[WARN] Dry-run chế độ target trống không đạt."
    echo "Nếu nguyên nhân là target/main đã có dữ liệu, có thể chuyển sang chế độ REPLACE MAIN."
    echo "Các branch/tag khác sẽ được giữ nguyên."
    echo
    if ! ui_yesno "Cho phép kiểm tra lại với chế độ REPLACE target/main?" "N"; then
      echo "[INFO] Đã hủy; không có thay đổi nào được thực hiện."
      ui_pause
      return
    fi

    replace_existing=1
    ui_section "REPLACE TARGET MAIN — DRY-RUN"
    ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --replace-existing --dry-run || {
      echo
      echo "[ERROR] Target không đủ điều kiện replace hoặc source/main không hợp lệ. Site chưa bị thay đổi."
      ui_pause
      return
    }
  fi

  echo
  if (( replace_existing == 1 )); then
    echo "CẢNH BÁO NGHIÊM TRỌNG: target/main hiện tại sẽ bị THAY THẾ bằng source/main."
    echo "Platform sẽ backup target/main tạm, replace bằng force-with-lease, verify SHA/tree,"
    echo "sau đó mới đổi origin site. Branch/tag khác của target vẫn được giữ nguyên."
    echo
    read -r -p "Nhập chính xác URL repo đích '$new_repo' để REPLACE main: " typed
    [[ "$typed" == "$new_repo" ]] || {
      echo "[INFO] Xác nhận không khớp; đã hủy."
      ui_pause
      return
    }

    ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --replace-existing --yes
  else
    echo "CẢNH BÁO: Bước tiếp theo sẽ GHI source/main vào repository đích đang trống."
    echo "Origin của site chỉ thay đổi sau khi push và verify thành công."
    ui_confirm_execute "BOOTSTRAP NEW REPOSITORY: $site → $new_repo" &&
      ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --yes
  fi

  ui_pause
}
