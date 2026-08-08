#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/backup/lib/backup.sh"

for fn in \
  backup_create \
  backup_verify \
  backup_restore \
  backup_resolve_id \
  backup_restore_dns_check \
  backup_restore_import_database
do
  grep -q "^${fn}()" "$F"
done

grep -q 'site_provision_configure_target' "$F"
grep -q 'site_provision_prepare_runtime' "$F"
grep -q 'site_provision_finalize_runtime' "$F"
grep -q 'site_provision_health' "$F"

if grep -q 'certbot ' "$F"; then
  echo "[ERROR] Backup Module không được gọi Certbot trực tiếp."
  exit 1
fi

bash -n "$F"

echo "[OK] Backup Restore dev.3"
