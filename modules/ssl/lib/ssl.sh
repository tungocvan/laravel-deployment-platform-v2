#!/usr/bin/env bash

platform_ssl_require() {
  require_command certbot
}

platform_ssl_validate_domain() {
  platform_nginx_validate_domain "${1:-}"
}

platform_ssl_live_dir() {
  local domain="$1"
  printf '/etc/letsencrypt/live/%s' "$domain"
}

platform_ssl_exists() {
  local domain="${1:-}"
  [[ -n "$domain" ]] || return 1
  local dir
  dir="$(platform_ssl_live_dir "$domain")"
  [[ -f "$dir/fullchain.pem" && -f "$dir/privkey.pem" ]]
}

platform_ssl_issue() {
  require_root
  platform_ssl_require

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform ssl issue <domain>"
  platform_ssl_validate_domain "$domain"

  platform_nginx_conflict_files "$domain" >/dev/null || true

  certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    -d "$domain"

  platform_ssl_verify "$domain"
  success "SSL issued/deployed: $domain"
}

platform_ssl_show() {
  platform_ssl_require

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform ssl show <domain>"
  platform_ssl_validate_domain "$domain"

  certbot certificates 2>/dev/null | awk -v d="$domain" '
    BEGIN{show=0}
    /^  Certificate Name:/{
      show=($0 ~ ("Certificate Name: " d "$"))
    }
    show{print}
  '
}

platform_ssl_verify() {
  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform ssl verify <domain>"
  platform_ssl_validate_domain "$domain"

  local dir
  dir="$(platform_ssl_live_dir "$domain")"

  [[ -f "$dir/fullchain.pem" ]] || die "Thiếu fullchain.pem: $domain"
  [[ -f "$dir/privkey.pem" ]] || die "Thiếu privkey.pem: $domain"
  [[ -r "$dir/fullchain.pem" ]] || die "Không đọc được fullchain.pem: $domain"
  [[ -r "$dir/privkey.pem" ]] || die "Không đọc được privkey.pem: $domain"

  if command -v openssl >/dev/null 2>&1; then
    openssl x509 -in "$dir/fullchain.pem" -noout -subject -issuer -dates
  fi

  success "SSL hợp lệ: $domain"
}

platform_ssl_renew() {
  require_root
  platform_ssl_require

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform ssl renew <domain>"
  platform_ssl_validate_domain "$domain"

  certbot renew --cert-name "$domain"
  platform_ssl_verify "$domain"
  success "SSL renew hoàn tất: $domain"
}

platform_ssl_remove() {
  require_root
  platform_ssl_require

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform ssl remove <domain>"
  platform_ssl_validate_domain "$domain"

  if ! platform_ssl_exists "$domain"; then
    echo "[INFO] Không có certificate: $domain"
    return 0
  fi

  # Refuse deleting if enabled Nginx configs still reference this certificate.
  local refs
  refs="$(grep -RIl "/etc/letsencrypt/live/$domain/" /etc/nginx/sites-enabled 2>/dev/null || true)"
  if [[ -n "$refs" ]]; then
    die "Certificate vẫn đang được Nginx sử dụng: $refs"
  fi

  certbot delete --non-interactive --cert-name "$domain"
  success "SSL removed: $domain"
}

platform_ssl_list() {
  platform_ssl_require
  certbot certificates
}
