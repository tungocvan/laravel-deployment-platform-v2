#!/usr/bin/env bash

ui_menu_sites() {
  while true; do
    ui_header
    ui_section "SITE MANAGEMENT"
    cat <<'EOF'

  1) Danh sách site
  2) Xem chi tiết site
  3) Site doctor
  4) Create site
  5) Duplicate site

  6) Enable
  7) Disable
  8) Maintenance ON
  9) Maintenance OFF

 10) Archive
 11) Restore archived site
 12) Danh sách archive
 13) Purge

  0) Back

EOF
    local c site
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_run site list; ui_pause ;;
      2) site="$(ui_select_site "Chọn site cần xem")" || continue; ui_run site show "$site"; ui_pause ;;
      3) site="$(ui_select_site "Chọn site cần kiểm tra")" || continue; ui_run site doctor "$site"; ui_pause ;;
      4) ui_flow_create ;;
      5) ui_flow_duplicate ;;
      6) site="$(ui_select_site "Chọn site cần ENABLE")" || continue; ui_confirm_execute "ENABLE SITE: $site" && ui_run_sudo site enable "$site" --yes; ui_pause ;;
      7) site="$(ui_select_site "Chọn site cần DISABLE")" || continue; ui_confirm_execute "DISABLE SITE: $site" && ui_run_sudo site disable "$site" --yes; ui_pause ;;
      8) site="$(ui_select_site "Chọn site")" || continue; ui_confirm_execute "MAINTENANCE ON: $site" && ui_run_sudo site maintenance on "$site"; ui_pause ;;
      9) site="$(ui_select_site "Chọn site")" || continue; ui_confirm_execute "MAINTENANCE OFF: $site" && ui_run_sudo site maintenance off "$site"; ui_pause ;;
      10) ui_flow_archive ;;
      11) ui_flow_restore_archive ;;
      12) ui_run site archives; ui_pause ;;
      13) ui_flow_purge ;;
      0) return 0 ;;
    esac
  done
}

ui_flow_create() {
  local strategy name domain repo branch ssl=1 choice
  ui_section "CREATE SITE"
  cat <<'EOF'
  1) Docker Platform hiện tại
  2) Docker theo repository
  3) Auto detect
  0) Back
EOF
  read -r -p "Chọn runtime: " choice
  case "$choice" in
    1) strategy="platform" ;;
    2) strategy="repository" ;;
    3) strategy="auto" ;;
    0) return 0 ;;
    *) echo "[ERROR] Lựa chọn không hợp lệ."; ui_pause; return ;;
  esac

  name="$(ui_prompt "Tên site mới")"
  [[ -n "$name" ]] || { echo "[ERROR] Tên site bắt buộc."; ui_pause; return; }
  domain="$(ui_prompt "Domain mới")"
  [[ -n "$domain" ]] || { echo "[ERROR] Domain bắt buộc."; ui_pause; return; }
  repo="$(ui_prompt "Git repository")"
  [[ -n "$repo" ]] || { echo "[ERROR] Repository bắt buộc."; ui_pause; return; }
  branch="$(ui_prompt "Git branch [main]")"; branch="${branch:-main}"
  ui_yesno "SSL?" "Y" || ssl=0

  local args=(site create "--name=$name" "--domain=$domain" "--repo=$repo" "--branch=$branch" "--docker=$strategy")
  [[ "$ssl" -eq 0 ]] && args+=(--no-ssl)

  ui_section "PREVIEW / DRY-RUN"
  ui_run_sudo "${args[@]}" --dry-run || { ui_pause; return; }
  ui_confirm_execute "CREATE: $name / $domain / $strategy" && ui_run_sudo "${args[@]}" --yes
  ui_pause
}

ui_flow_duplicate() {
  local source name domain copydb=0 copystorage=0 ssl=1
  source="$(ui_select_site "Chọn site nguồn")" || return 0
  name="$(ui_prompt "Tên site mới")"
  [[ -n "$name" ]] || { echo "[ERROR] Tên site bắt buộc."; ui_pause; return; }
  domain="$(ui_prompt "Domain mới")"
  [[ -n "$domain" ]] || { echo "[ERROR] Domain bắt buộc."; ui_pause; return; }
  ui_yesno "Copy database?" "Y" && copydb=1
  ui_yesno "Copy storage?" "N" && copystorage=1
  ui_yesno "SSL?" "Y" || ssl=0
  local args=(site duplicate "--from=$source" "--name=$name" "--domain=$domain")
  [[ "$copydb" -eq 1 ]] && args+=(--copy-db)
  [[ "$copystorage" -eq 1 ]] && args+=(--copy-storage)
  [[ "$ssl" -eq 0 ]] && args+=(--no-ssl)
  ui_section "PREVIEW / DRY-RUN"
  ui_run_sudo "${args[@]}" --dry-run || { ui_pause; return; }
  ui_confirm_execute "DUPLICATE: $source → $name / $domain" && ui_run_sudo "${args[@]}" --yes
  ui_pause
}

ui_flow_archive() {
  local site
  site="$(ui_select_site "Chọn site cần ARCHIVE")" || return 0
  ui_section "ARCHIVE DRY-RUN"
  ui_run_sudo site archive "$site" --dry-run || { ui_pause; return; }
  ui_confirm_execute "ARCHIVE SITE: $site" && ui_run_sudo site archive "$site" --yes
  ui_pause
}

ui_flow_restore_archive() {
  ui_run site archives; echo
  local site
  site="$(ui_prompt "Tên archived site cần khôi phục")"
  [[ -n "$site" ]] || return 0
  ui_confirm_execute "RESTORE ARCHIVE: $site" && ui_run_sudo site restore-archive "$site" --yes
  ui_pause
}

ui_flow_purge() {
  ui_run site archives; echo
  local site typed
  site="$(ui_prompt "Tên site/archive cần PURGE")"
  [[ -n "$site" ]] || return 0
  ui_section "PURGE DRY-RUN"
  ui_run_sudo site purge "$site" --dry-run || { ui_pause; return; }
  echo; echo "CẢNH BÁO: PURGE là thao tác phá huỷ vĩnh viễn runtime resources."
  read -r -p "Nhập chính xác '$site' để tiếp tục: " typed
  [[ "$typed" == "$site" ]] || { echo "[INFO] Đã hủy."; ui_pause; return; }
  ui_run_sudo site purge "$site" --yes
  ui_pause
}
