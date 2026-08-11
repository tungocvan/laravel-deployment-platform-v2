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
  5) Update site from GitHub
  6) Change domain
  7) Duplicate site

  8) Enable
  9) Disable
 10) Maintenance ON
 11) Maintenance OFF

 12) Archive
 13) Restore archived site
 14) Danh sách archive
 15) Purge
 16) Repair SSL
 17) Environment (.env)
 18) Storage

  0) Back

EOF
    local c site
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_run site list; ui_pause ;;
      2) site="$(ui_select_site "Chọn site cần xem")" || continue; ui_run site show "$site"; ui_pause ;;
      3) site="$(ui_select_site "Chọn site cần kiểm tra")" || continue; ui_run site doctor "$site"; ui_pause ;;
      4) ui_flow_create ;;
      5) ui_flow_update ;;
      6) ui_flow_change_domain ;;
      7) ui_flow_duplicate ;;
      8) site="$(ui_select_site "Chọn site cần ENABLE")" || continue; ui_confirm_execute "ENABLE SITE: $site" && ui_run_sudo site enable "$site" --yes; ui_pause ;;
      9) site="$(ui_select_site "Chọn site cần DISABLE")" || continue; ui_confirm_execute "DISABLE SITE: $site" && ui_run_sudo site disable "$site" --yes; ui_pause ;;
      10) site="$(ui_select_site "Chọn site")" || continue; ui_confirm_execute "MAINTENANCE ON: $site" && ui_run_sudo site maintenance on "$site"; ui_pause ;;
      11) site="$(ui_select_site "Chọn site")" || continue; ui_confirm_execute "MAINTENANCE OFF: $site" && ui_run_sudo site maintenance off "$site"; ui_pause ;;
      12) ui_flow_archive ;;
      13) ui_flow_restore_archive ;;
      14) ui_run site archives; ui_pause ;;
      15) ui_flow_purge ;;
      16) ui_flow_repair_ssl ;;
      17) ui_flow_env ;;
      18) ui_flow_storage ;;
      0) return 0 ;;
    esac
  done
}

ui_flow_create() {
  local strategy name domain repo branch ssl=1 choice replace_domain=0 domain_rc=0
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

  ui_section "DOMAIN / SSL PREFLIGHT"
  ui_run site domain-preflight "$domain" || domain_rc=$?
  case "$domain_rc" in
    0) ;;
    10)
      ui_yesno "Domain có Nginx config cũ do Platform quản lý. Làm mới config?" "N" \
        || { echo "[INFO] Đã hủy Create."; ui_pause; return; }
      replace_domain=1
      ;;
    11)
      ui_yesno "DNS chưa trỏ đúng VPS. Tạo site KHÔNG SSL?" "N" \
        || { echo "[INFO] Đã hủy Create."; ui_pause; return; }
      ssl=0
      ;;
    12)
      ui_yesno "Domain có Nginx config cũ do Platform quản lý. Làm mới config?" "N" \
        || { echo "[INFO] Đã hủy Create."; ui_pause; return; }
      replace_domain=1
      ui_yesno "DNS chưa trỏ đúng VPS. Tạo site KHÔNG SSL?" "N" \
        || { echo "[INFO] Đã hủy Create."; ui_pause; return; }
      ssl=0
      ;;
    21|22)
      echo "[ERROR] Domain conflict không thể tự động ghi đè."
      ui_pause
      return
      ;;
    *)
      echo "[ERROR] Domain preflight thất bại (exit=$domain_rc)."
      ui_pause
      return
      ;;
  esac

  repo="$(ui_prompt "Git repository")"
  [[ -n "$repo" ]] || { echo "[ERROR] Repository bắt buộc."; ui_pause; return; }
  branch="$(ui_prompt "Git branch [main]")"; branch="${branch:-main}"
  if [[ "$ssl" -eq 1 ]]; then
    ui_yesno "SSL?" "Y" || ssl=0
  else
    echo "[INFO] SSL đã tắt do DNS preflight."
  fi

  local args=(site create "--name=$name" "--domain=$domain" "--repo=$repo" "--branch=$branch" "--docker=$strategy")
  [[ "$ssl" -eq 0 ]] && args+=(--no-ssl)
  [[ "$replace_domain" -eq 1 ]] && args+=(--replace-domain-config)

  ui_section "PREVIEW / DRY-RUN"
  ui_run_sudo "${args[@]}" --dry-run || { ui_pause; return; }
  ui_confirm_execute "CREATE: $name / $domain / $strategy" && ui_run_sudo "${args[@]}" --yes
  ui_pause
}

ui_flow_update() {
  local site
  site="$(ui_select_site "Chọn site cần UPDATE từ GitHub")" || return 0
  ui_section "UPDATE SITE / DRY-RUN"
  ui_run_sudo site update "$site" --dry-run || { ui_pause; return; }
  ui_confirm_execute "UPDATE FROM GITHUB: $site" && ui_run_sudo site update "$site" --yes
  ui_pause
}

ui_flow_change_domain() {
  local site domain ssl=1 domain_rc=0 replace_domain=0
  site="$(ui_select_site "Chọn site cần đổi domain")" || return 0
  domain="$(ui_prompt "Domain mới")"
  [[ -n "$domain" ]] || { echo "[ERROR] Domain bắt buộc."; ui_pause; return; }

  ui_section "NEW DOMAIN / SSL PREFLIGHT"
  ui_run site domain-preflight "$domain" || domain_rc=$?
  case "$domain_rc" in
    0) ;;
    10)
      ui_yesno "Domain có Nginx config cũ do Platform quản lý. Làm mới config?" "N" \
        || { echo "[INFO] Đã hủy Change Domain."; ui_pause; return; }
      replace_domain=1
      ;;
    11)
      ui_yesno "DNS chưa trỏ đúng VPS. Đổi domain KHÔNG SSL?" "N" \
        || { echo "[INFO] Đã hủy Change Domain."; ui_pause; return; }
      ssl=0
      ;;
    12)
      ui_yesno "Domain có Nginx config cũ do Platform quản lý. Làm mới config?" "N" \
        || { echo "[INFO] Đã hủy Change Domain."; ui_pause; return; }
      replace_domain=1
      ui_yesno "DNS chưa trỏ đúng VPS. Đổi domain KHÔNG SSL?" "N" \
        || { echo "[INFO] Đã hủy Change Domain."; ui_pause; return; }
      ssl=0
      ;;
    21|22)
      echo "[ERROR] Domain conflict không thể tự động ghi đè."
      ui_pause
      return
      ;;
    *)
      echo "[ERROR] Domain preflight thất bại (exit=$domain_rc)."
      ui_pause
      return
      ;;
  esac

  local args=(site change-domain "$site" "--domain=$domain")
  [[ "$ssl" -eq 0 ]] && args+=(--no-ssl)
  [[ "$replace_domain" -eq 1 ]] && args+=(--replace-domain-config)

  ui_section "CHANGE DOMAIN / DRY-RUN"
  ui_run_sudo "${args[@]}" --dry-run || { ui_pause; return; }
  ui_confirm_execute "CHANGE DOMAIN: $site -> $domain" && ui_run_sudo "${args[@]}" --yes
  ui_pause
}

ui_flow_repair_ssl() {
  local site
  site="$(ui_select_site "Chọn site cần Repair SSL")" || return 0
  ui_section "REPAIR SSL"
  ui_confirm_execute "REPAIR SSL: $site" && ui_run_sudo site repair-ssl "$site"
  ui_pause
}

ui_flow_env() {
  local site choice key value backup
  site="$(ui_select_site "Chọn site cần quản lý .env")" || return 0
  while true; do
    ui_section "ENVIRONMENT: $site"
    cat <<'EOF'
  1) Status / permission check
  2) Get key
  3) Set key (safe + auto rollback)
  4) Backup .env
  5) Restore latest backup
  6) Validate
  7) Refresh Laravel cache only
  0) Back
EOF
    read -r -p "Chọn: " choice
    case "$choice" in
      1) ui_run_sudo site env "$site" status; ui_pause ;;
      2)
        key="$(ui_prompt "ENV key")"; [[ -n "$key" ]] || continue
        ui_run_sudo site env "$site" get "$key"; ui_pause
        ;;
      3)
        key="$(ui_prompt "ENV key")"; [[ -n "$key" ]] || continue
        value="$(ui_prompt "ENV value")"
        ui_confirm_execute "SET ENV SAFE: $site / $key" && ui_run_sudo site env "$site" set "$key" "$value"
        ui_pause
        ;;
      4) ui_run_sudo site env "$site" backup; ui_pause ;;
      5)
        ui_confirm_execute "RESTORE LATEST ENV BACKUP: $site" && ui_run_sudo site env "$site" restore latest
        ui_pause
        ;;
      6) ui_run_sudo site env "$site" validate; ui_pause ;;
      7)
        ui_confirm_execute "REFRESH LARAVEL CACHE ONLY: $site" && ui_run_sudo site env "$site" refresh
        ui_pause
        ;;
      0) return 0 ;;
    esac
  done
}

ui_flow_storage() {
  local site choice relative source
  site="$(ui_select_site "Chọn site cần quản lý storage")" || return 0
  while true; do
    ui_section "STORAGE: $site"
    cat <<'EOF'
  1) Status
  2) Repair permissions/link
  3) List path
  4) Put file từ VPS vào persistent storage
  0) Back
EOF
    read -r -p "Chọn: " choice
    case "$choice" in
      1) ui_run_sudo site storage "$site" status; ui_pause ;;
      2) ui_confirm_execute "REPAIR STORAGE: $site" && ui_run_sudo site storage "$site" repair; ui_pause ;;
      3)
        relative="$(ui_prompt "Path trong storage [app/public]")"; relative="${relative:-app/public}"
        ui_run_sudo site storage "$site" list "$relative"; ui_pause
        ;;
      4)
        source="$(ui_prompt "Source file trên VPS, ví dụ /tmp/logo.png")"
        relative="$(ui_prompt "Destination trong storage, ví dụ app/public/logo.png")"
        [[ -n "$source" && -n "$relative" ]] || { echo "[ERROR] Source và destination bắt buộc."; ui_pause; continue; }
        ui_confirm_execute "PUT STORAGE: $source -> storage/$relative" && ui_run_sudo site storage "$site" put "--source=$source" "--path=$relative"
        ui_pause
        ;;
      0) return 0 ;;
    esac
  done
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
