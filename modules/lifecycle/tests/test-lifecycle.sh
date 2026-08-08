#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/lifecycle/lib/lifecycle.sh"

for fn in \
  site_disable site_enable site_maintenance \
  site_archive site_restore_archive site_archives \
  site_lifecycle_show
do
  grep -q "^${fn}()" "$F"
done

grep -q 'backup_verify "$site"' "$F"
grep -q 'down --remove-orphans' "$F"

if grep -q 'down -v' "$F"; then
  echo "[ERROR] Lifecycle archive không được purge volumes."
  exit 1
fi

bash -n "$F"
echo "[OK] Site Lifecycle v1.1 dev.1"
