#!/usr/bin/env bash

site_domain_ipv4_local() {
  if [[ -n "${PLATFORM_PUBLIC_IP:-}" ]]; then printf '%s\n' "$PLATFORM_PUBLIC_IP"; fi
  command -v ip >/dev/null 2>&1 || return 0
  ip -4 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | sort -u
}

site_domain_ipv6_local() {
  if [[ -n "${PLATFORM_PUBLIC_IPV6:-}" ]]; then printf '%s\n' "$PLATFORM_PUBLIC_IPV6"; fi
  command -v ip >/dev/null 2>&1 || return 0
  ip -6 -o addr show scope global 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | sort -u
}

site_domain_dns_ipv4() {
  getent ahostsv4 "$1" 2>/dev/null | awk '{print $1}' | sort -u
}

site_domain_dns_ipv6() {
  getent ahostsv6 "$1" 2>/dev/null | awk '{print $1}' | grep ':' | sort -u
}

site_domain_all_in_set() {
  local values="$1" allowed="$2" value
  [[ -n "$values" && -n "$allowed" ]] || return 1
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    grep -Fxq "$value" <<<"$allowed" || return 1
  done <<<"$values"
}

site_domain_preflight() {
  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform site domain-preflight <domain>"
  platform_nginx_validate_domain "$domain"

  echo "===== DOMAIN PREFLIGHT ====="
  echo "Domain: $domain"

  local inventory_name
  inventory_name="$(inventory_get_field "$domain" name 2>/dev/null || true)"
  if [[ -n "$inventory_name" ]]; then
    echo "[ERROR] Domain đang thuộc managed site: $inventory_name"
    return 21
  fi
  echo "[OK] Inventory: domain chưa được sử dụng"

  local conflicts="" file foreign=0 managed=0
  conflicts="$(platform_nginx_conflict_files "$domain" 2>/dev/null || true)"
  if [[ -n "$conflicts" ]]; then
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if platform_nginx_is_managed_file "$file"; then
        managed=1
        echo "[WARN] Nginx managed config đã tồn tại: $file"
      else
        foreign=1
        echo "[ERROR] Nginx foreign config đã tồn tại: $file"
      fi
    done <<<"$conflicts"
  else
    echo "[OK] Nginx: không có domain conflict"
  fi
  [[ "$foreign" -eq 0 ]] || return 22

  local dns4 dns6 local4 local6 dns_ok=1
  dns4="$(site_domain_dns_ipv4 "$domain")"
  dns6="$(site_domain_dns_ipv6 "$domain")"
  local4="$(site_domain_ipv4_local)"
  local6="$(site_domain_ipv6_local)"

  echo "DNS IPv4 : ${dns4//$'\n'/, }"
  [[ -n "$dns6" ]] && echo "DNS IPv6 : ${dns6//$'\n'/, }"
  echo "VPS IPv4 : ${local4//$'\n'/, }"
  [[ -n "$local6" ]] && echo "VPS IPv6 : ${local6//$'\n'/, }"

  if [[ -n "$dns4" ]]; then
    site_domain_all_in_set "$dns4" "$local4" || dns_ok=0
  fi
  if [[ -n "$dns6" ]]; then
    site_domain_all_in_set "$dns6" "$local6" || dns_ok=0
  fi
  [[ -n "$dns4$dns6" ]] || dns_ok=0

  if [[ "$dns_ok" -eq 1 ]]; then
    echo "[OK] DNS đang trỏ đúng VPS"
    echo "[OK] SSL preflight: eligible"
  else
    echo "[WARN] DNS chưa trỏ hoàn toàn về VPS"
    echo "[WARN] SSL preflight: không nên cấp SSL tự động"
  fi

  if [[ "$managed" -eq 1 ]]; then
    [[ "$dns_ok" -eq 1 ]] && return 10 || return 12
  fi
  [[ "$dns_ok" -eq 1 ]] || return 11
  return 0
}
