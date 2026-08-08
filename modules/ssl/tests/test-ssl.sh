#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/ssl/lib/ssl.sh"

for fn in \
  platform_ssl_issue \
  platform_ssl_verify \
  platform_ssl_remove \
  platform_ssl_exists
do
  grep -q "^${fn}()" "$F"
done

grep -q 'certbot --nginx' "$F"
grep -q 'certbot delete' "$F"

echo "[OK] SSL Module files"
