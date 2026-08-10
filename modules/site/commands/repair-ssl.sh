#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/nginx/lib/nginx.sh"
source "$PLATFORM_HOME/modules/ssl/lib/ssl.sh"

key="${1:-}"
[[ -n "$key" ]] || die "USAGE: platform site repair-ssl <site>"

inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"
name="$(inventory_get_field "$key" name)"
domain="$(inventory_get_field "$key" domain)"
[[ -n "$domain" ]] || die "Site không có domain trong Inventory: $key"

echo "[SSL REPAIR] Site: $name"
echo "[SSL REPAIR] Domain: $domain"
platform_ssl_ensure "$domain"

inventory_init
python3 - "$(inventory_file)" "$name" <<'PY'
import datetime,json,os,sys
path,name=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
for item in d.get("sites",[]):
    if str(item.get("name","")) == name:
        item["ssl_status"]="active"
        item["ssl_checked_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
        break
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2); f.write("\n")
os.replace(tmp,path)
PY

success "SSL repair hoàn tất: $domain"
