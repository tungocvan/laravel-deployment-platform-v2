#!/usr/bin/env bash

ui_menu_sites() {
  while true; do
    ui_header
    ui_section "SITE MANAGEMENT"
    cat <<'EOF'

  1) Create Site
  2) Danh sách site
  3) Xem chi tiết site
  4) Site doctor
  5) Duplicate site

  6) Enable
  7) Disable
  8) Maintenance ON
  9) Maintenance OFF

 10) Archive
 11) Restore archived site
 12) Danh sách archive
 13) Purge
 14) Purge Force (active site)
 15) Update kho mới (main cùng dòng source)
 16) Khởi tạo kho mới trống từ kho cũ

  0) Back

EOF
    local c site
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_flow_create ;;
      2) ui_run site list; ui_pause ;;
      3)
        site="$(ui_select_site "Chọn site cần xem")" || continue
        ui_run site show "$site"; ui_pause ;;
      4)
        site="$(ui_select_site "Chọn site cần kiểm tra")" || continue
        ui_run site doctor "$site"; ui_pause ;;
      5) ui_flow_duplicate ;;
      6)
        site="$(ui_select_site "Chọn site cần ENABLE")" || continue
        ui_confirm_execute "ENABLE SITE: $site" && ui_run_sudo site enable "$site" --yes
        ui_pause ;;
      7)
        site="$(ui_select_site "Chọn site cần DISABLE")" || continue
        ui_confirm_execute "DISABLE SITE: $site" && ui_run_sudo site disable "$site" --yes
        ui_pause ;;
      8)
        site="$(ui_select_site "Chọn site")" || continue
        ui_confirm_execute "MAINTENANCE ON: $site" && ui_run_sudo site maintenance on "$site"
        ui_pause ;;
      9)
        site="$(ui_select_site "Chọn site")" || continue
        ui_confirm_execute "MAINTENANCE OFF: $site" && ui_run_sudo site maintenance off "$site"
        ui_pause ;;
      10) ui_flow_archive ;;
      11) ui_flow_restore_archive ;;
      12) ui_run site archives; ui_pause ;;
      13) ui_flow_purge ;;
      14) ui_flow_purge_force ;;
      15) ui_flow_update_repository ;;
      16) ui_flow_bootstrap_repository ;;
      0) return 0 ;;
    esac
  done
}

ui_flow_create() {
  local name domain repo branch ssl=1
  local default_repo="${PLATFORM_DEFAULT_SITE_REPO:-git@github.com:tungocvan/laravel-shop.git}"

  name="$(ui_prompt "Tên site mới")"
  [[ -n "$name" ]] || { echo "[ERROR] Tên site bắt buộc."; ui_pause; return; }

  domain="$(ui_prompt "Domain")"
  [[ -n "$domain" ]] || { echo "[ERROR] Domain bắt buộc."; ui_pause; return; }

  repo="$(ui_prompt "Git repository [$default_repo]")"
  repo="${repo:-$default_repo}"

  branch="$(ui_prompt "Git branch [main]")"
  branch="${branch:-main}"
  ui_yesno "SSL?" "Y" || ssl=0

  local args=(site create "--name=$name" "--domain=$domain" "--repo=$repo" "--branch=$branch")
  [[ "$ssl" -eq 0 ]] && args+=(--no-ssl)

  ui_section "CREATE SITE DRY-RUN"
  ui_run_sudo "${args[@]}" --dry-run || { ui_pause; return; }

  ui_confirm_execute "CREATE SITE: $name / $domain" &&
    ui_run_sudo "${args[@]}" --yes
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

  ui_confirm_execute "DUPLICATE: $source → $name / $domain" &&
    ui_run_sudo "${args[@]}" --yes
  ui_pause
}

ui_flow_archive() {
  local site
  site="$(ui_select_site "Chọn site cần ARCHIVE")" || return 0
  ui_section "ARCHIVE DRY-RUN"
  ui_run_sudo site archive "$site" --dry-run || { ui_pause; return; }
  ui_confirm_execute "ARCHIVE SITE: $site" &&
    ui_run_sudo site archive "$site" --yes
  ui_pause
}

ui_flow_restore_archive() {
  ui_run site archives
  echo
  local site
  site="$(ui_prompt "Tên archived site cần khôi phục")"
  [[ -n "$site" ]] || return 0
  ui_confirm_execute "RESTORE ARCHIVE: $site" &&
    ui_run_sudo site restore-archive "$site" --yes
  ui_pause
}

ui_flow_purge() {
  ui_run site archives
  echo
  local site
  site="$(ui_prompt "Tên archive cần PURGE")"
  [[ -n "$site" ]] || return 0

  ui_section "PURGE DRY-RUN"
  ui_run_sudo site purge "$site" --dry-run || { ui_pause; return; }

  echo
  echo "CẢNH BÁO: PURGE là thao tác phá huỷ vĩnh viễn runtime resources."
  local typed
  read -r -p "Nhập chính xác '$site' để tiếp tục: " typed
  [[ "$typed" == "$site" ]] || { echo "[INFO] Đã hủy."; ui_pause; return; }

  ui_run_sudo site purge "$site" --yes
  ui_pause
}

ui_flow_purge_force() {
  local site
  site="$(ui_select_site "Chọn ACTIVE SITE cần PURGE FORCE")" || return 0

  ui_section "PURGE FORCE DRY-RUN"
  ui_run_sudo site purge "$site" --force-active --dry-run || { ui_pause; return; }

  echo
  echo "CẢNH BÁO NGHIÊM TRỌNG: PURGE FORCE xoá trực tiếp active site, KHÔNG cần Archive."
  echo "Backup safety vẫn được giữ và purge history vẫn được ghi."
  local typed
  read -r -p "Nhập chính xác '$site' để PURGE FORCE: " typed
  [[ "$typed" == "$site" ]] || { echo "[INFO] Đã hủy."; ui_pause; return; }

  ui_run_sudo site purge "$site" --force-active --yes
  ui_pause
}

ui_flow_update_repository() {
  local site new_repo
  site="$(ui_select_site "Chọn site cần UPDATE KHO MỚI")" || return 0

  ui_section "UPDATE KHO MỚI — MAIN LINEAGE CHECK"
  echo "Platform chỉ cho đổi địa chỉ repository khi:"
  echo "  - Site đang ở branch main"
  echo "  - Kho mới/main chứa đầy đủ history của kho cũ/main"
  echo "  - Kho mới có thể bằng hoặc đi trước kho cũ"
  echo "  - Working tree source sạch"
  echo "  - Không update code, không deploy"
  echo
  ui_run site show "$site"
  echo

  new_repo="$(ui_prompt "Địa chỉ Git repository mới")"
  [[ -n "$new_repo" ]] || { echo "[ERROR] Repository mới bắt buộc."; ui_pause; return; }

  ui_section "VERIFY / DRY-RUN"
  ui_run_sudo git migrate-remote "$site" "--to=$new_repo" --require-compatible-main --dry-run || {
    echo
    echo "[ERROR] Kho mới không cùng dòng source main hoặc không đủ điều kiện. Không có thay đổi nào được thực hiện."
    ui_pause
    return
  }

  echo
  ui_confirm_execute "UPDATE REPOSITORY ADDRESS: $site → $new_repo" &&
    ui_run_sudo git migrate-remote "$site" "--to=$new_repo" --require-compatible-main --yes
  ui_pause
}

ui_flow_bootstrap_repository() {
  local site new_repo
  site="$(ui_select_site "Chọn site cần KHỞI TẠO KHO MỚI")" || return 0

  ui_section "KHỞI TẠO KHO MỚI TRỐNG TỪ KHO CŨ"
  echo "Quy trình an toàn:"
  echo "  - Đọc source chuẩn trực tiếp từ kho cũ/main"
  echo "  - Kho mới bắt buộc hoàn toàn trống"
  echo "  - Không lấy source local của project để tạo kho mới"
  echo "  - Khi thực thi sẽ kiểm tra quyền ghi + xóa bằng ref tạm"
  echo "  - Push old/main -> new/main và verify SHA + tree 100%"
  echo "  - Chỉ sau verify mới đổi origin của site và sync Inventory"
  echo "  - HEAD/worktree/deploy/database/container được giữ nguyên"
  echo
  ui_run site show "$site"
  echo

  new_repo="$(ui_prompt "Địa chỉ Git repository MỚI VÀ TRỐNG")"
  [[ -n "$new_repo" ]] || { echo "[ERROR] Repository mới bắt buộc."; ui_pause; return; }

  ui_section "BOOTSTRAP VERIFY / DRY-RUN"
  ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --dry-run || {
    echo
    echo "[ERROR] Kho mới không trống hoặc source/main không đủ điều kiện. Site chưa bị thay đổi."
    ui_pause
    return
  }

  echo
  echo "CẢNH BÁO: Bước tiếp theo sẽ GHI main vào repository mới."
  echo "Origin của site chỉ thay đổi sau khi push và verify thành công."
  ui_confirm_execute "BOOTSTRAP NEW REPOSITORY: $site → $new_repo" &&
    ui_run_sudo git bootstrap-remote "$site" "--to=$new_repo" --yes
  ui_pause
}
