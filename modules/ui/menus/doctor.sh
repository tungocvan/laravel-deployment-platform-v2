#!/usr/bin/env bash

ui_menu_doctor() {
  while true; do
    ui_header
    ui_section "DOMAIN / DOCTOR"
    cat <<'EOF'

  1) Check domain
  2) Check domain + proposed site identity
  3) Site doctor

  0) Back

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
