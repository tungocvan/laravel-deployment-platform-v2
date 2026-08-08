#!/usr/bin/env bash

ui_menu_packages() {
  while true; do
    ui_header
    ui_section "PACKAGES"
    cat <<'EOF'

  1) List packages
  2) Show package
  3) Verify package
  4) Package history

  0) Back

EOF
    local c pkg
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_run package list; ui_pause ;;
      2|3|4)
        pkg="$(ui_prompt "Package ID (vd: Package-013)")"
        [[ -n "$pkg" ]] || continue
        case "$c" in
          2) ui_run package show "$pkg" ;;
          3) ui_run package verify "$pkg" ;;
          4) ui_run package history "$pkg" ;;
        esac
        ui_pause ;;
      0) return 0 ;;
    esac
  done
}
