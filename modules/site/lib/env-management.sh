#!/usr/bin/env bash

# Site-aware .env management. Editing is always performed on a staging copy;
# the production .env is only changed through site_ops_env_apply().
site_ops_env_list_keys() {
  require_root
  local site="${1:-}" path env
  [[ -n "$site" ]] || die "USAGE: platform site env <site> --keys"
  path="$(site_runtime_path "$site")"
  env="$path/.env"
  [[ -f "$env" ]] || die "Site thiếu .env: $path"

  echo "========================================================="
  echo "SITE ENVIRONMENT KEYS — VALUES REDACTED"
  echo "========================================================="
  echo "Site : $site"
  echo "Path : $path"
  echo "File : $env"
  echo
  site_ops_env_keys "$env" | sed 's/^/  - /'
}

site_ops_env_edit() {
  require_root
  local site="${1:-}" path env staged editor rc=0
  [[ -n "$site" ]] || die "USAGE: platform site env <site> --edit"
  path="$(site_runtime_path "$site")"
  env="$path/.env"
  [[ -f "$env" ]] || die "Site thiếu .env: $path"

  staged="$(mktemp)"
  cp -p "$env" "$staged"
  trap 'rm -f "$staged"' RETURN

  editor="${EDITOR:-}"
  if [[ -z "$editor" ]]; then
    if command -v nano >/dev/null 2>&1; then editor="nano"
    elif command -v vi >/dev/null 2>&1; then editor="vi"
    else die "Không tìm thấy editor. Đặt EDITOR hoặc cài nano/vi."
    fi
  fi

  echo "[STAGING] Đang chỉnh bản sao tạm của $env"
  echo "          Production .env chưa bị thay đổi."
  "$editor" "$staged"

  echo
  site_ops_env_apply "$site" "$staged" --dry-run || rc=$?
  [[ "$rc" -eq 0 ]] || die "Preview .env không đạt safety checks (exit=$rc)."
  echo
  site_confirm "Apply staged .env update cho site '$site'?" || { echo "[CANCELLED] Production .env không thay đổi."; return 0; }
  site_ops_env_apply "$site" "$staged" --yes
}
