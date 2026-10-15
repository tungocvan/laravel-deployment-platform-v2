#!/usr/bin/env bash

ui_menu_packages() {
  while true; do
    ui_header
    ui_section "PACKAGES — INVENTORY / VERIFY / HISTORY"
    cat <<'EOF'

  1) Danh sách gói chức năng
     Liệt kê các package và module được Platform quản lý.

  2) Chi tiết gói chức năng
     Xem thông tin và cấu hình của package được chọn.

  3) Kiểm tra tính toàn vẹn gói
     Xác minh contract và tính nhất quán của package.

  4) Lịch sử gói chức năng
     Xem các thay đổi của package theo lịch sử lưu trữ.

  0) Quay lại

EOF
    local c pkg
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_run package list; ui_pause ;;
      2|3|4)
        pkg="$(ui_prompt "Package ID (vd: Package-013)")"
        [[ -n "$pkg" ]] || continue
        case "$c" in
          2) ui_run package show "$pkg" ;;
          3) ui_run package verify "$pkg" ;;
          4) ui_run package history "$pkg" ;;
        esac
        ui_pause ;;
      0) return 0 ;;
    esac
  done
}
