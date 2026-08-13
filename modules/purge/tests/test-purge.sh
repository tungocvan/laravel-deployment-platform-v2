#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/purge/lib/purge.sh"
UI="$ROOT/modules/ui/menus/sites.sh"
HELP="$ROOT/modules/site/commands/help.sh"

for fn in site_purge site_purge_resolve_json site_purge_write_history site_purge_source_is_managed site_purge_nginx_remove; do
  grep -q "^${fn}()" "$F"
done

grep -q 'backup_verify' "$F"
grep -q 'down -v --remove-orphans' "$F"
grep -q -- '--force-active' "$F"
grep -q 'PURGE.ACTIVE_REQUIRES_FORCE' "$F"
grep -q 'PURGE.SOURCE_PATH_UNMANAGED' "$F"
grep -q '/opt/\$slug/repo' "$F"
grep -q '/opt/projects/\*' "$F"

# Regression: destructive Nginx errors must not be hidden by >/dev/null 2>&1.
! grep -q 'platform_nginx_remove .*2>&1' "$F"

grep -q 'Purge Force (active site)' "$UI"
grep -q 'ui_flow_purge_force()' "$UI"
grep -q 'site purge .*--force-active --yes' "$HELP"

bash -n "$F"
bash -n "$UI"
bash -n "$HELP"
echo "[OK] Site Purge regression + force-active"
