#!/usr/bin/env bash

site_disable_tx_enable_nginx() {
  local domain="$1"
  platform_nginx_enable "$domain" >/dev/null 2>&1
}

site_disable_tx_start_docker() {
  local path="$1"
  deploy_compose "$path" up -d >/dev/null 2>&1
}

site_disable_tx_audit() {
  local site="$1" result="$2" error_code="$3" tx_id="$4" rollback_status="$5"
  platform_audit_try site disable "$site" "$result" "$error_code" "$tx_id" "$rollback_status"
}

site_disable_tx_rollback() {
  warn "Disable thất bại. Rollback best-effort..."
  if platform_tx_rollback; then
    return 0
  fi

  warn "Disable rollback có $(platform_tx_rollback_failures) bước thất bại."
  return 1
}

# Platform 2.1 transactional override for site disable only.
# lifecycle.sh remains the owner of the surrounding lifecycle business model.
site_disable() {
  require_root
  local site="${1:-}" auto_yes=0 arg
  shift || true
  [[ -n "$site" ]] || die "USAGE: platform site disable <site> [--yes]"
  for arg in "$@"; do
    case "$arg" in --yes) auto_yes=1 ;; *) die "Option không hợp lệ: $arg" ;; esac
  done

  local resolved path domain state rc tx_id rollback_status
  resolved="$(site_lifecycle_resolve "$site")"
  path="${resolved%%|*}"; domain="${resolved#*|}"
  state="$(site_lifecycle_read_state "$site")"

  if [[ "$state" == "disabled" ]]; then
    success "Site đã disabled: $site"
    return 0
  fi

  [[ "$auto_yes" -eq 1 ]] || site_lifecycle_confirm "Disable site?" || die "Đã hủy."

  echo "[01/05] Validate runtime"
  deploy_compose "$path" config >/dev/null

  tx_id="site-disable:$site"
  platform_tx_begin "$tx_id" || die "Không thể bắt đầu transaction disable site."

  echo "[02/05] Disable Nginx"
  if platform_nginx_disable "$domain"; then
    if platform_tx_register site_disable_tx_enable_nginx "$domain"; then
      :
    else
      rc=$?
      if site_disable_tx_rollback; then rollback_status="success"; else rollback_status="partial"; fi
      site_disable_tx_audit "$site" failed SITE.DISABLE_TX_REGISTER_FAILED "$tx_id" "$rollback_status"
      return "$rc"
    fi
  else
    rc=$?
    platform_tx_rollback >/dev/null 2>&1 || true
    site_disable_tx_audit "$site" failed SITE.DISABLE_NGINX_FAILED "$tx_id" not-required
    return "$rc"
  fi

  echo "[03/05] Stop Docker"
  if deploy_compose "$path" stop; then
    if platform_tx_register site_disable_tx_start_docker "$path"; then
      :
    else
      rc=$?
      if site_disable_tx_rollback; then rollback_status="success"; else rollback_status="partial"; fi
      site_disable_tx_audit "$site" failed SITE.DISABLE_TX_REGISTER_FAILED "$tx_id" "$rollback_status"
      return "$rc"
    fi
  else
    rc=$?
    if site_disable_tx_rollback; then rollback_status="success"; else rollback_status="partial"; fi
    site_disable_tx_audit "$site" failed SITE.DISABLE_DOCKER_FAILED "$tx_id" "$rollback_status"
    return "$rc"
  fi

  echo "[04/05] Record lifecycle"
  if site_lifecycle_write_state "$site" "disabled" "user-request"; then
    :
  else
    rc=$?
    if site_disable_tx_rollback; then rollback_status="success"; else rollback_status="partial"; fi
    site_disable_tx_audit "$site" failed SITE.DISABLE_STATE_FAILED "$tx_id" "$rollback_status"
    return "$rc"
  fi

  platform_tx_commit || die "Không thể commit transaction disable site."
  site_disable_tx_audit "$site" success "" "$tx_id" not-required

  echo "[05/05] Done"
  success "Site disabled: $site"
}
