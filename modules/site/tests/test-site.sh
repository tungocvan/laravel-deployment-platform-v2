#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
SITE="$ROOT/modules/site/lib/site.sh"
PROV="$ROOT/modules/site/lib/provision.sh"

[[ -f "$PROV" ]]
for fn in \
  site_provision_configure_target \
  site_provision_prepare_runtime \
  site_provision_finalize_runtime \
  site_provision_health \
  site_provision_commit_inventory \
  site_provision_cleanup_new_target
do
  grep -q "^${fn}()" "$PROV"
done

grep -q 'site_provision_configure_target' "$SITE"
grep -q 'site_provision_prepare_runtime' "$SITE"
grep -q 'platform_ssl_issue' "$SITE"

if grep -q 'certbot ' "$SITE"; then
  echo "[ERROR] Site Module không được gọi Certbot trực tiếp."
  exit 1
fi

echo "[OK] Site Provisioning Engine v3.1 dev.1"
