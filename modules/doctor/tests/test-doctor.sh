#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/doctor/lib/doctor.sh"

for fn in \
  doctor_domain \
  doctor_domain_dns \
  doctor_inventory_site_json_by_field \
  doctor_backup_info \
  doctor_find_free_port_value
do
  grep -q "^${fn}()" "$F"
done

grep -q 'EXISTING SITE' "$F"
grep -q 'Latest backup' "$F"
grep -q 'HTTP port khả dụng tiếp theo' "$F"

bash -n "$F"
echo "[OK] Doctor Module dev.2"
