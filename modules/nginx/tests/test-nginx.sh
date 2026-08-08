#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
FILE="$ROOT/modules/nginx/lib/nginx.sh"

for fn in \
  platform_nginx_conflict_files \
  platform_nginx_render \
  platform_nginx_enable \
  platform_nginx_ensure_proxy \
  platform_nginx_remove
do
  grep -q "^${fn}()" "$FILE"
done

grep -q 'Managed by Laravel Deployment Platform' "$ROOT/templates/nginx/laravel-proxy.conf.tpl"
grep -q 'server_name {{DOMAIN}};' "$ROOT/templates/nginx/laravel-proxy.conf.tpl"
grep -q 'proxy_pass http://127.0.0.1:{{HTTP_PORT}};' "$ROOT/templates/nginx/laravel-proxy.conf.tpl"

echo "[OK] Nginx Module files"
