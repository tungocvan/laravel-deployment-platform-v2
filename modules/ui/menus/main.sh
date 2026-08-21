#!/usr/bin/env bash

ui_quick_guide() {
  while true; do
    ui_header
    ui_section "HƯỚNG DẪN NHANH — CHỌN ĐÚNG CHỨC NĂNG"
    cat <<'EOF'

  TÌNH HUỐNG THƯỜNG GẶP
  ---------------------
  • Tạo / xóa / bật tắt / bảo trì site
      → Sites & Repository

  • Code trên GitHub có thay đổi
      → Deploy → Update Code from GitHub
      → sau đó Full Deploy nếu thay đổi cần build/migrate/runtime refresh

  • Chỉ sửa hoặc thêm biến .env thông thường
      → Deploy → Backend → Optimize / Reload .env
      → sau đó Health Check
      → KHÔNG cần Full Deploy nếu không đổi image/port/service secret

  • Website lỗi 500 / 502 hoặc nghi runtime có vấn đề
      → Deploy → Health Check
      → Doctor & Domain Diagnostics nếu cần kiểm tra sâu hơn

  • Backup trước khi thao tác nguy hiểm / phục hồi dữ liệu
      → Backup & Restore

  • SSL / Nginx / domain proxy có vấn đề
      → Infrastructure — SSL & Nginx

  • Đổi repository nhưng giữ nguyên source
      → Sites & Repository → Update repository

  • Tạo repository mới hoặc đồng bộ hai repository
      → Sites & Repository → Bootstrap / Sync repository

  • Kiểm tra quyền GitHub / tạo SSH key riêng cho repository
      → Sites & Repository → Kiểm tra quyền repository / SSH key
      → Platform test READ + WRITE + DELETE bằng ref tạm, không chạm main
      → Nếu thiếu quyền, có thể tạo key theo owner/repo và in PUBLIC KEY

  NGUYÊN TẮC AN TOÀN
  ------------------
  1. Ưu tiên Dry-run / Health trước thao tác thay đổi lớn.
  2. Full Deploy dùng khi cần build image + migrate + optimize + runtime health.
  3. Optimize dùng cho thay đổi Laravel config/.env thông thường, nhanh hơn Full Deploy.
  4. Deploy chỉ thành công khi Laravel boot và HTTP application trả 2xx/3xx.
  5. Backup trước Archive/Purge/Restore hoặc thay đổi dữ liệu quan trọng.
  6. Không bao giờ chia sẻ private SSH key; menu chỉ hiển thị public key .pub.

  0) Back

EOF
    local c
    read -r -p "Chọn: " c
    case "$c" in
      0|q|Q) return 0 ;;
      *) ;;
    esac
  done
}

# Professional top-level navigation. Each item advertises its main capabilities
# so operators do not need to enter a submenu just to discover what it does.
ui_main() {
  while true; do
    ui_header
    cat <<'EOF'

  OPERATIONS CONSOLE
  ------------------

  1) Sites & Repository
     Create/List/Doctor, Enable/Disable, Maintenance, Archive/Purge,
     đổi kho, tạo kho mới, đồng bộ 2 kho Git, kiểm tra quyền Git/SSH

  2) Backup & Restore
     Create/List/Verify backup, Restore site hiện tại hoặc tạo site mới

  3) Deploy & Runtime
     Git Update, Full Deploy, Backend (Migrate/Optimize/Health),
     Frontend Build, Health Check, Container Status

  4) Doctor & Domain Diagnostics
     Kiểm tra domain, site identity và chẩn đoán site

  5) Infrastructure — SSL & Nginx
     SSL issue/list/verify/renew, Nginx verify/show/conflict

  6) Packages
     List/Show/Verify package và xem lịch sử package

  7) Hướng dẫn sử dụng / Chọn đúng chức năng
     Quick guide cho .env, deploy, lỗi 500/502, backup, repository, SSL

  0) Exit

EOF
    local choice
    read -r -p "Chọn chức năng: " choice
    case "$choice" in
      1) ui_menu_sites ;;
      2) ui_menu_backup ;;
      3) ui_menu_deploy ;;
      4) ui_menu_doctor ;;
      5) ui_menu_infrastructure ;;
      6) ui_menu_packages ;;
      7) ui_quick_guide ;;
      0|q|Q) return 0 ;;
      *) ;;
    esac
  done
}
