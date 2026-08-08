#!/usr/bin/env bash

ui_menu_backup() {
  while true; do
    ui_header
    ui_section "BACKUP / RESTORE"

    if ui_restore_state_exists; then
      echo
      echo "[INFO] Có Restore trước đang pending/failed."
      ui_restore_state_show || true
      echo
      cat <<'EOF'
  1) Resume last Restore
  2) Create backup
  3) List backups
  4) Verify backup
  5) Restore existing site
  6) Restore as new site
  7) Discard pending Restore

  0) Back
EOF
    else
      cat <<'EOF'

  1) Create backup
  2) List backups
  3) Verify backup
  4) Restore existing site
  5) Restore as new site

  0) Back
EOF
    fi

    echo
    local c site backup
    read -r -p "Chọn: " c

    if ui_restore_state_exists; then
      case "$c" in
        1) ui_flow_restore_resume ;;
        2)
          site="$(ui_select_site "Chọn site cần backup")" || continue
          ui_confirm_execute "CREATE BACKUP: $site" &&
            ui_run_sudo backup create "$site"
          ui_pause ;;
        3)
          site="$(ui_select_site "Chọn site")" || continue
          ui_run backup list "$site"
          ui_pause ;;
        4)
          site="$(ui_select_site "Chọn site")" || continue
          backup="$(ui_select_backup "$site")" || continue
          ui_run_sudo backup verify "$site" "$backup"
          ui_pause ;;
        5) ui_flow_restore_existing ;;
        6) ui_flow_restore_new ;;
        7)
          ui_confirm_execute "DISCARD PENDING RESTORE" &&
            ui_restore_state_clear
          ui_pause ;;
        0) return 0 ;;
      esac
    else
      case "$c" in
        1)
          site="$(ui_select_site "Chọn site cần backup")" || continue
          ui_confirm_execute "CREATE BACKUP: $site" &&
            ui_run_sudo backup create "$site"
          ui_pause ;;
        2)
          site="$(ui_select_site "Chọn site")" || continue
          ui_run backup list "$site"
          ui_pause ;;
        3)
          site="$(ui_select_site "Chọn site")" || continue
          backup="$(ui_select_backup "$site")" || continue
          ui_run_sudo backup verify "$site" "$backup"
          ui_pause ;;
        4) ui_flow_restore_existing ;;
        5) ui_flow_restore_new ;;
        0) return 0 ;;
      esac
    fi
  done
}

ui_restore_execute_existing() {
  local site="$1" backup="$2" domain="$3" ssl_mode="$4"
  local args=(backup restore "$site" "$backup" --yes)
  [[ "$ssl_mode" == "no-ssl" ]] && args+=(--no-ssl)

  ui_restore_state_save "restore-existing" "$site" "$backup" "$site" "$domain" "" "$ssl_mode"

  if ui_run_sudo "${args[@]}"; then
    ui_restore_state_clear
    echo "[OK] Restore thành công. Pending state đã được xóa."
    return 0
  fi

  ui_restore_state_mark_failed "restore-existing failed"
  ui_command_failed "Restore"
  return 1
}

ui_restore_execute_new() {
  local source="$1" backup="$2" name="$3" domain="$4" database="$5" ssl_mode="$6"
  local args=(
    backup restore "$source" "$backup"
    "--as=$name"
    "--domain=$domain"
    "--database=$database"
    --yes
  )
  [[ "$ssl_mode" == "no-ssl" ]] && args+=(--no-ssl)

  ui_restore_state_save "restore-as-new" "$source" "$backup" "$name" "$domain" "$database" "$ssl_mode"

  if ui_run_sudo "${args[@]}"; then
    ui_restore_state_clear
    echo "[OK] Restore-as-new thành công. Pending state đã được xóa."
    return 0
  fi

  ui_restore_state_mark_failed "restore-as-new failed"
  ui_command_failed "Restore-as-new"
  return 1
}

ui_flow_restore_existing() {
  local site backup domain ssl_mode
  site="$(ui_select_site "Chọn site cần restore")" || return 0
  backup="$(ui_select_backup "$site")" || return 0
  domain="$(inventory_get_field "$site" domain 2>/dev/null || true)"

  ui_section "RESTORE DRY-RUN"
  if ! ui_run_sudo backup restore "$site" "$backup" --dry-run; then
    ui_command_failed "Restore dry-run"
    ui_pause
    return 0
  fi

  if [[ -n "$domain" ]]; then
    if ! ui_restore_ssl_gate "$domain"; then
      echo "[INFO] Đã hủy Restore."
      ui_pause
      return 0
    fi
  fi
  ssl_mode="${UI_RESTORE_SSL_MODE:-normal}"

  ui_confirm_execute "RESTORE: $site ← $backup" || {
    ui_pause
    return 0
  }

  ui_restore_execute_existing "$site" "$backup" "$domain" "$ssl_mode" || true
  ui_pause
}

ui_flow_restore_new() {
  local source backup name domain database ssl_mode

  source="$(ui_select_site "Chọn site chứa backup nguồn")" || return 0
  backup="$(ui_select_backup "$source")" || return 0

  name="$(ui_prompt "Tên site mới")"
  [[ -n "$name" ]] || {
    echo "[ERROR] Tên site bắt buộc."
    ui_pause
    return 0
  }

  domain="$(ui_prompt "Domain mới")"
  [[ -n "$domain" ]] || {
    echo "[ERROR] Domain bắt buộc."
    ui_pause
    return 0
  }

  database="$(ui_prompt "Database mới" "db_$(printf '%s' "$name" | tr '-' '_')")"

  local base_args=(
    backup restore "$source" "$backup"
    "--as=$name"
    "--domain=$domain"
    "--database=$database"
  )

  ui_section "RESTORE-AS-NEW DRY-RUN"
  if ! ui_run_sudo "${base_args[@]}" --dry-run; then
    ui_command_failed "Restore-as-new dry-run"
    ui_pause
    return 0
  fi

  if ! ui_restore_ssl_gate "$domain"; then
    echo "[INFO] Đã hủy Restore."
    ui_pause
    return 0
  fi
  ssl_mode="${UI_RESTORE_SSL_MODE:-normal}"

  ui_confirm_execute "RESTORE-AS-NEW: $source/$backup → $name / $domain" || {
    ui_pause
    return 0
  }

  ui_restore_execute_new "$source" "$backup" "$name" "$domain" "$database" "$ssl_mode" || true
  ui_pause
}

ui_flow_restore_resume() {
  ui_header
  ui_section "RESUME LAST RESTORE"

  ui_restore_state_show || {
    echo "[INFO] Không có pending Restore."
    ui_pause
    return 0
  }

  local mode source backup target domain database ssl_mode
  mode="$(ui_restore_state_field mode)"
  source="$(ui_restore_state_field source_site)"
  backup="$(ui_restore_state_field backup)"
  target="$(ui_restore_state_field target_site)"
  domain="$(ui_restore_state_field domain)"
  database="$(ui_restore_state_field database)"
  ssl_mode="$(ui_restore_state_field ssl_mode)"
  [[ -n "$ssl_mode" ]] || ssl_mode="normal"

  echo
  if [[ "$mode" == "restore-existing" ]]; then
    echo "[INFO] Chạy lại dry-run trước khi Resume."
    if ! ui_run_sudo backup restore "$source" "$backup" --dry-run; then
      ui_command_failed "Resume dry-run"
      ui_pause
      return 0
    fi

    if [[ -n "$domain" ]]; then
      if ! ui_restore_ssl_gate "$domain"; then
        echo "[INFO] Đã hủy Resume."
        ui_pause
        return 0
      fi
      ssl_mode="${UI_RESTORE_SSL_MODE:-$ssl_mode}"
    fi

    ui_confirm_execute "RESUME RESTORE: $source ← $backup" || {
      ui_pause
      return 0
    }

    ui_restore_execute_existing "$source" "$backup" "$domain" "$ssl_mode" || true
    ui_pause
    return 0
  fi

  if [[ "$mode" == "restore-as-new" ]]; then
    local base_args=(
      backup restore "$source" "$backup"
      "--as=$target"
      "--domain=$domain"
      "--database=$database"
    )

    echo "[INFO] Chạy lại dry-run trước khi Resume."
    if ! ui_run_sudo "${base_args[@]}" --dry-run; then
      ui_command_failed "Resume restore-as-new dry-run"
      ui_pause
      return 0
    fi

    if ! ui_restore_ssl_gate "$domain"; then
      echo "[INFO] Đã hủy Resume."
      ui_pause
      return 0
    fi
    ssl_mode="${UI_RESTORE_SSL_MODE:-$ssl_mode}"

    ui_confirm_execute "RESUME RESTORE-AS-NEW: $source/$backup → $target / $domain" || {
      ui_pause
      return 0
    }

    ui_restore_execute_new "$source" "$backup" "$target" "$domain" "$database" "$ssl_mode" || true
    ui_pause
    return 0
  fi

  echo "[ERROR] Pending Restore state không hợp lệ: mode=$mode"
  ui_pause
}
