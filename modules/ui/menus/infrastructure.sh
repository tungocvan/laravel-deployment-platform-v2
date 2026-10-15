#!/usr/bin/env bash

ui_menu_infrastructure() {
  while true; do
    ui_header
    ui_section "INFRASTRUCTURE — SSL CERTIFICATES / NGINX ROUTING"
    cat <<'EOF'

  SSL CERTIFICATES
  ----------------
  1) Hướng dẫn cấp chứng chỉ SSL
     Kiểm tra DNS và điều kiện trước khi cấp chứng chỉ.

  2) Danh sách chứng chỉ SSL
     Liệt kê các chứng chỉ đang được quản lý.

  3) Xác minh chứng chỉ SSL
     Kiểm tra chứng chỉ của tên miền được chọn.

  4) Xem chi tiết chứng chỉ SSL
     Hiển thị thông tin chứng chỉ và tên miền.

  5) Gia hạn chứng chỉ SSL
     Yêu cầu xác nhận trước khi gia hạn.

  NGINX
  -----
  6) Kiểm tra cấu hình Nginx
     Xác minh cấu hình máy chủ web.

  7) Xem cấu hình tên miền
     Hiển thị routing và cấu hình Nginx của domain.

  8) Kiểm tra xung đột Nginx
     Phát hiện xung đột domain và server block.

  0) Quay lại

EOF
    local c domain
    read -r -p "Chọn: " c

    case "$c" in
      1)
        domain="$(ui_prompt "Domain cần SSL")"
        [[ -n "$domain" ]] && ui_ssl_wizard "$domain" || true
        ui_pause
        ;;
      2)
        ui_run ssl list
        ui_pause
        ;;
      3)
        domain="$(ui_prompt "Domain")"
        [[ -n "$domain" ]] && ui_run_sudo ssl verify "$domain"
        ui_pause
        ;;
      4)
        domain="$(ui_prompt "Domain")"
        [[ -n "$domain" ]] && ui_run ssl show "$domain"
        ui_pause
        ;;
      5)
        domain="$(ui_prompt "Domain")"
        if [[ -n "$domain" ]]; then
          ui_confirm_execute "RENEW SSL: $domain" &&
            ui_run_sudo ssl renew "$domain"
        fi
        ui_pause
        ;;
      6)
        ui_run_sudo nginx verify
        ui_pause
        ;;
      7)
        domain="$(ui_prompt "Domain")"
        [[ -n "$domain" ]] && ui_run nginx show "$domain"
        ui_pause
        ;;
      8)
        domain="$(ui_prompt "Domain")"
        [[ -n "$domain" ]] && ui_run_sudo nginx conflicts "$domain"
        ui_pause
        ;;
      0)
        return 0
        ;;
    esac
  done
}
