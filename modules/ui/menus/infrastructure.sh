#!/usr/bin/env bash

ui_menu_infrastructure() {
  while true; do
    ui_header
    ui_section "INFRASTRUCTURE — SSL CERTIFICATES / NGINX ROUTING"
    cat <<'EOF'

  SSL CERTIFICATES
  ----------------
  1) SSL Wizard — kiểm tra DNS/preflight rồi cấp chứng chỉ an toàn
  2) SSL List — liệt kê certificate đang quản lý
  3) SSL Verify — xác minh certificate của một domain
  4) SSL Show — xem chi tiết certificate/domain
  5) SSL Renew — gia hạn certificate

  NGINX
  -----
  6) Nginx Verify — kiểm tra cấu hình Nginx tổng thể
  7) Nginx Show Domain — xem routing/config của một domain
  8) Nginx Conflicts — kiểm tra xung đột domain/server block

  0) Back

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
