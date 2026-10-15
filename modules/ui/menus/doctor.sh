#!/usr/bin/env bash

ui_menu_doctor() {
  while true; do
    ui_header
    ui_section "DOCTOR & DOMAIN DIAGNOSTICS — DNS / IDENTITY / SITE HEALTH"
    cat <<'EOF'

  1) Kiểm tra tên miền
     Kiểm tra DNS và khả năng sẵn sàng của domain.

  2) Kiểm tra tên miền và định danh website
     Đối chiếu tên site, database dự kiến trước khi tạo mới.

  3) Chẩn đoán website
     Kiểm tra source, Docker runtime, worker và bản sao lưu.

  0) Quay lại

EOF
    local c domain name database site
    read -r -p "Chọn: " c
    case "$c" in
      1)
        domain="$(ui_prompt "Domain")"
        [[ -n "$domain" ]] && ui_run_sudo doctor domain "$domain"
        ui_pause ;;
      2)
        domain="$(ui_prompt "Domain")"
        name="$(ui_prompt "Tên site dự kiến")"
        database="$(ui_prompt "Database dự kiến" "db_$(printf '%s' "$name" | tr '-' '_')")"
        [[ -n "$domain" && -n "$name" ]] &&
          ui_run_sudo doctor domain "$domain" "--name=$name" "--database=$database"
        ui_pause ;;
      3)
        site="$(ui_select_site "Chọn site")" || continue
        ui_run site doctor "$site"; ui_pause ;;
      0) return 0 ;;
    esac
  done
}
