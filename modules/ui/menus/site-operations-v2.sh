#!/usr/bin/env bash

# Production Site Operations V2 override. Legacy flow functions remain reused.
ui_flow_production_update() {
  local site rc=0 migrate=0
  site="$(ui_select_site "Chọn site cần UPDATE")" || return 0

  # Preview may intentionally return 3 when migration is required. Do not let
  # set -e abort the menu; turn that state into an explicit operator decision.
  ui_run_sudo site update "$site" --dry-run || rc=$?
  echo
  case "$rc" in
    0) ;;
    3)
      echo "[WARNING] Update này chứa database migration."
      echo "          Khi apply, Platform sẽ tạo verified backup checkpoint trước migration."
      echo "          Migration chỉ chạy khi bạn xác nhận riêng bước này."
      if ui_yesno "Cho phép chạy migration cho UPDATE SITE: $site ?" "N"; then
        migrate=1
      else
        echo "[CANCELLED] Không chạy update vì migration chưa được operator chấp thuận."
        ui_pause
        return 0
      fi
      ;;
    *)
      echo "[BLOCKED] Preview Update Site không đạt safety checks (exit=$rc). Không apply."
      ui_pause
      return 0
      ;;
  esac

  if ui_confirm_execute "UPDATE SITE: $site"; then
    if [[ "$migrate" -eq 1 ]]; then
      ui_run_sudo site update "$site" --migrate --yes
    else
      ui_run_sudo site update "$site" --yes
    fi
  fi
  ui_pause
}

ui_menu_sites() {
  while true; do
    ui_header
    ui_section "SITES — PRODUCTION OPERATIONS / LIFECYCLE / REPOSITORY"
    cat <<'EOF'

  PRODUCTION SITE OPERATIONS
  --------------------------
  1) Create Site
  2) Update Site — Git fast-forward + runtime reconcile
  3) Update .env — key-only diff + safe reconcile
  4) Production Diagnostics — read-only evidence
  5) Run Artisan — app service auto-discovery
  6) Runtime / Docker Status — topology + health + ports
  7) Production Cleanup — report-only mặc định

  INSPECTION / LIFECYCLE
  ----------------------
  8) Danh sách site
  9) Xem chi tiết site
 10) Site Doctor
 11) Duplicate Site
 12) Enable
 13) Disable
 14) Maintenance ON
 15) Maintenance OFF

  ARCHIVE / DELETE
  ----------------
 16) Archive
 17) Restore archived site
 18) Danh sách archive
 19) Purge
 20) Purge Force (active site)

  REPOSITORY MANAGEMENT
  ---------------------
 21) Update repository
 22) Bootstrap repository mới trống
 23) Sync repositories
 24) Repository access / SSH

  0) Back
EOF
    local c site cmd env_file
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_flow_create ;;
      2) ui_flow_production_update ;;
      3) site="$(ui_select_site "Chọn site cần UPDATE .env")" || continue; env_file="$(ui_prompt "Đường dẫn file .env mới")"; [[ -f "$env_file" ]] || { echo "[ERROR] File không tồn tại."; ui_pause; continue; }; ui_run_sudo site env "$site" "$env_file" --dry-run; echo; ui_confirm_execute "UPDATE .env: $site" && ui_run_sudo site env "$site" "$env_file" --yes; ui_pause ;;
      4) site="$(ui_select_site "Chọn site")" || continue; ui_run site diagnostics "$site"; ui_pause ;;
      5) site="$(ui_select_site "Chọn site")" || continue; cmd="$(ui_prompt "Artisan command (vd: about, route:list)")"; [[ -n "$cmd" ]] && ui_run_sudo site artisan "$site" $cmd; ui_pause ;;
      6) site="$(ui_select_site "Chọn site")" || continue; ui_run site runtime "$site"; ui_pause ;;
      7) site="$(ui_select_site "Chọn site")" || continue; ui_run site cleanup "$site"; echo; ui_yesno "Thực thi cleanup site-local?" "N" && ui_run_sudo site cleanup "$site" --apply --yes; ui_pause ;;
      8) ui_run site list; ui_pause ;;
      9) site="$(ui_select_site "Chọn site cần xem")" || continue; ui_run site show "$site"; ui_pause ;;
      10) site="$(ui_select_site "Chọn site cần kiểm tra")" || continue; ui_run site doctor "$site"; ui_pause ;;
      11) ui_flow_duplicate ;;
      12) site="$(ui_select_site "Chọn site cần ENABLE")" || continue; ui_confirm_execute "ENABLE SITE: $site" && ui_run_sudo site enable "$site" --yes; ui_pause ;;
      13) site="$(ui_select_site "Chọn site cần DISABLE")" || continue; ui_confirm_execute "DISABLE SITE: $site" && ui_run_sudo site disable "$site" --yes; ui_pause ;;
      14) site="$(ui_select_site "Chọn site")" || continue; ui_confirm_execute "MAINTENANCE ON: $site" && ui_run_sudo site maintenance on "$site"; ui_pause ;;
      15) site="$(ui_select_site "Chọn site")" || continue; ui_confirm_execute "MAINTENANCE OFF: $site" && ui_run_sudo site maintenance off "$site"; ui_pause ;;
      16) ui_flow_archive ;;
      17) ui_flow_restore_archive ;;
      18) ui_run site archives; ui_pause ;;
      19) ui_flow_purge ;;
      20) ui_flow_purge_force ;;
      21) ui_flow_update_repository ;;
      22) ui_flow_bootstrap_repository ;;
      23) ui_flow_sync_repositories ;;
      24) ui_flow_repository_access ;;
      0) return 0 ;;
    esac
  done
}
