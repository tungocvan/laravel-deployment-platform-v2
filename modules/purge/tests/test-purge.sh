#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/purge/lib/purge.sh"

for fn in site_purge site_purge_resolve_json site_purge_write_history; do
  grep -q "^${fn}()" "$F"
done

grep -q 'backup_verify' "$F"
grep -q 'down -v --remove-orphans' "$F"
grep -q 'Refuse auto-purge source ngoài /opt/projects' "$F"
bash -n "$F"
echo "[OK] Site Purge dev.1"
