#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"
F="$ROOT/modules/doctor/lib/doctor.sh"
SITE_F="$ROOT/modules/doctor/lib/site.sh"
SITE_CMD="$ROOT/modules/doctor/commands/site.sh"

for fn in \
  doctor_domain \
  doctor_domain_dns \
  doctor_inventory_site_json_by_field \
  doctor_backup_info \
  doctor_find_free_port_value
do
  grep -q "^${fn}()" "$F"
done

for fn in \
  doctor_site \
  doctor_site_service_state
do
  grep -q "^${fn}()" "$SITE_F"
done

grep -q 'EXISTING SITE' "$F"
grep -q 'Latest backup' "$F"
grep -q 'HTTP port khả dụng tiếp theo' "$F"
grep -q 'Git working tree' "$SITE_F"
grep -q 'for service in db redis app socket web' "$SITE_F"
grep -q 'for service in queue queue-admission-documents scheduler' "$SITE_F"
grep -Fq 'doctor_ok "service $service: healthy/running"' "$SITE_F"
grep -Fq 'doctor_warn "worker $service: $state"' "$SITE_F"
grep -q 'doctor_backup_info' "$SITE_F"
grep -q 'modules/inventory/lib/inventory.sh' "$SITE_CMD"
grep -q 'modules/git/lib/git.sh' "$SITE_CMD"
grep -q 'modules/deploy/lib/deploy.sh' "$SITE_CMD"

bash -n "$F"
bash -n "$SITE_F"
bash -n "$SITE_CMD"
echo "[OK] Doctor Module domain + managed site diagnostics"
