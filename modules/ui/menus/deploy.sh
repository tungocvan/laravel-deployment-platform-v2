#!/usr/bin/env bash

ui_deploy_detect_field() {
  local json="$1" field="$2"
  ui_json_field "$json" "$field"
}

ui_deploy_wizard_summary() {
  local site="$1" detect="$2"
  local path laravel package_json pm pm_available vite build owner manifest strategy docker_services
  path="$(ui_deploy_detect_field "$detect" path)"
  laravel="$(ui_deploy_detect_field "$detect" laravel)"
  package_json="$(ui_deploy_detect_field "$detect" package_json)"
  pm="$(ui_deploy_detect_field "$detect" package_manager)"
  pm_available="$(ui_deploy_detect_field "$detect" package_manager_available)"
  vite="$(ui_deploy_detect_field "$detect" vite)"
  build="$(ui_deploy_detect_field "$detect" build_script)"
  owner="$(ui_deploy_detect_field "$detect" project_owner)"
  manifest="$(ui_deploy_detect_field "$detect" vite_manifest_exists)"
  strategy="$(ui_deploy_detect_field "$detect" frontend_strategy)"
  docker_services="$(ui_deploy_detect_field "$detect" docker_services)"

  ui_line
  echo " DEPLOY & RUNTIME — $site"
  ui_line
  printf 'Site              : %s\n' "$site"
  printf 'Path              : %s\n' "${path:-N/A}"
  printf 'Laravel           : %s\n' "$([[ "$laravel" == "True" || "$laravel" == "true" ]] && echo YES || echo NO)"
  printf 'package.json      : %s\n' "$([[ "$package_json" == "True" || "$package_json" == "true" ]] && echo YES || echo NO)"
  printf 'Vite              : %s\n' "$([[ "$vite" == "True" || "$vite" == "true" ]] && echo YES || echo NO)"
  printf 'Build script      : %s\n' "$([[ "$build" == "True" || "$build" == "true" ]] && echo YES || echo NO)"
  printf 'Frontend strategy : %s\n' "${strategy:-N/A}"

  if [[ "$strategy" == "docker-multistage" ]]; then
    printf 'Docker services   : %s\n' "${docker_services:-app web}"
    printf 'Host Node/npm     : NOT REQUIRED\n'
  else
    printf 'Package manager   : %s\n' "${pm:-N/A}"
    printf 'Manager ready     : %s\n' "$([[ "$pm_available" == "True" || "$pm_available" == "true" ]] && echo YES || echo NO)"
    printf 'Project owner     : %s\n' "${owner:-N/A}"
  fi

  printf 'Vite manifest     : %s\n' "$([[ "$manifest" == "True" || "$manifest" == "true" ]] && echo PRESENT || echo NOT PRESENT)"
  ui_line
}

ui_deploy_frontend_menu() {
  local site="$1"
  while true; do
    ui_header
    ui_section "FRONTEND BUILD & DEPENDENCIES — $site"

    local detect
    detect="$("$UI_PLATFORM_BIN" deploy frontend detect "$site" 2>/dev/null)" || {
      echo "[ERROR] Không detect được frontend project."
      ui_pause
      return 1
    }
    ui_deploy_wizard_summary "$site" "$detect"

    cat <<'EOF'

  1) Production Build — build frontend assets theo Docker/project strategy
  2) Install Dependencies — cài package dependencies cho frontend
  3) Show package scripts — xem các npm/yarn/pnpm scripts khả dụng
  4) Detect again — quét lại frontend strategy và trạng thái build

  0) Back
EOF
    echo
    local c
    read -r -p "Chọn: " c
    case "$c" in
      1)
        ui_confirm_execute "FRONTEND PRODUCTION BUILD: $site" &&
          ui_run_sudo deploy frontend build "$site"
        ui_pause
        ;;
      2)
        ui_confirm_execute "INSTALL FRONTEND DEPENDENCIES: $site" &&
          ui_run_sudo deploy frontend install "$site"
        ui_pause
        ;;
      3)
        ui_run deploy frontend scripts "$site"
        ui_pause
        ;;
      4) ;;
      0) return 0 ;;
    esac
  done
}

ui_deploy_backend_menu() {
  local site="$1"
  while true; do
    ui_header
    ui_section "BACKEND / LARAVEL RUNTIME — $site"
    cat <<'EOF'

  1) Migrate Database — chạy php artisan migrate --force
  2) Optimize / Reload .env — refresh Laravel cache/config và restart runtime
     Dùng mục này khi chỉ thêm/sửa biến .env thông thường; nhanh hơn Full Deploy.
  3) Health Check — kiểm tra services, Laravel boot và HTTP application 2xx/3xx

  0) Back
EOF
    echo
    local c
    read -r -p "Chọn: " c
    case "$c" in
      1)
        ui_confirm_execute "MIGRATE DATABASE: $site" &&
          ui_run_sudo deploy migrate "$site"
        ui_pause ;;
      2)
        ui_confirm_execute "OPTIMIZE / RELOAD .ENV: $site" &&
          ui_run_sudo deploy optimize "$site"
        ui_pause ;;
      3)
        ui_run deploy health "$site"
        ui_pause ;;
      0) return 0 ;;
    esac
  done
}

ui_deploy_git_update() {
  local site="$1"
  ui_section "GIT UPDATE — PREVIEW / DRY-RUN"
  ui_run_sudo git update "$site" --dry-run || { ui_pause; return; }
  echo
  ui_confirm_execute "UPDATE CODE FROM GITHUB: $site" &&
    ui_run_sudo git update "$site" --yes
  ui_pause
}

ui_deploy_wizard() {
  local site
  site="$(ui_select_site "Chọn site cần Deploy / Runtime")" || return 0

  while true; do
    ui_header

    local detect
    detect="$("$UI_PLATFORM_BIN" deploy frontend detect "$site" 2>/dev/null || true)"

    if [[ -n "$detect" ]]; then
      ui_deploy_wizard_summary "$site" "$detect"
    else
      ui_line
      echo " DEPLOY & RUNTIME"
      ui_line
      echo "Site : $site"
      echo "[INFO] Frontend detection không khả dụng; Backend/Full Deploy vẫn dùng được."
      ui_line
    fi

    cat <<'EOF'

  1) Update Code from GitHub — fetch + fast-forward source, không tự deploy

  2) Full Deploy — build images + Docker up + migrate + optimize + runtime/HTTP health
     Dùng khi source/build/container thay đổi; đây là quy trình đầy đủ và lâu hơn.

  3) Backend / Laravel Runtime (Migrate, Optimize/Reload .env, Health)
     Dùng cho DB migration hoặc thay đổi .env/config mà không cần rebuild image.

  4) Frontend (Build, Dependencies, Scripts, Detect)
     Quản lý frontend assets và package manager.

  5) Health Check — Services + Laravel Boot + Public Storage + Application HTTP
     Nên chạy đầu tiên khi site lỗi 500/502 hoặc sau thay đổi runtime.

  6) Container Status — xem trạng thái Docker services của site

  7) Repair Public Storage — sửa quyền storage/app/public và verify /storage/* qua Nginx
     Dùng khi upload logo/favicon/file thành công nhưng URL /storage/... trả 403.

  0) Back
EOF
    echo

    local c
    read -r -p "Chọn: " c
    case "$c" in
      1)
        ui_deploy_git_update "$site"
        ;;
      2)
        ui_confirm_execute "FULL DEPLOY: $site" &&
          ui_run_sudo deploy run "$site"
        ui_pause
        ;;
      3)
        ui_deploy_backend_menu "$site"
        ;;
      4)
        if [[ -z "$detect" ]]; then
          echo "[ERROR] Package-006 frontend API chưa sẵn sàng."
          ui_pause
        else
          ui_deploy_frontend_menu "$site"
        fi
        ;;
      5)
        ui_run deploy health "$site"
        ui_pause
        ;;
      6)
        ui_run deploy status "$site"
        ui_pause
        ;;
      7)
        ui_confirm_execute "REPAIR PUBLIC STORAGE: $site" &&
          ui_run_sudo deploy health "$site" --storage-only
        ui_pause
        ;;
      0)
        return 0
        ;;
    esac
  done
}

ui_menu_deploy() {
  ui_deploy_wizard
}
