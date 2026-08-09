#!/usr/bin/env bash

# Create-site-only SSL policy.
# This file is sourced after modules/ssl/lib/ssl.sh by site create, so it
# intentionally overrides platform_ssl_issue only in that command process.
# Standalone `platform ssl issue` remains strict.

platform_ssl_issue() {
  require_root
  platform_ssl_require

  local domain="${1:-}"
  [[ -n "$domain" ]] || die "USAGE: platform ssl issue <domain>"
  platform_ssl_validate_domain "$domain"

  platform_nginx_conflict_files "$domain" >/dev/null || true

  if certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    -d "$domain"; then
    if platform_ssl_verify "$domain"; then
      success "SSL issued/deployed: $domain"
      return 0
    fi
  fi

  warn "Không cấp được SSL cho $domain; site vẫn được giữ ở HTTP. Có thể chạy lại: platform ssl issue $domain"
  return 0
}

site_create_record_ssl_status() {
  local name="$1" domain="$2" requested="$3"
  local status="skipped"

  if [[ "$requested" -eq 1 ]]; then
    if platform_ssl_exists "$domain" && platform_ssl_verify "$domain" >/dev/null 2>&1; then
      status="active"
    else
      status="failed"
    fi
  fi

  inventory_init
  python3 - "$(inventory_file)" "$name" "$status" <<'PY'
import json,sys,os,datetime
path,name,status=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
site=None
for item in d.get("sites",[]):
    if str(item.get("name","")) == name:
        site=item
        break
if site is None:
    raise SystemExit(0)
site["ssl_status"]=status
site["ssl_checked_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2)
    f.write("\n")
os.replace(tmp,path)
PY
}
