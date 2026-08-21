#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/purge/lib/purge.sh"
POLICY="$ROOT/modules/purge/lib/backup-policy.sh"
CMD="$ROOT/modules/site/commands/purge.sh"
CREATE_CMD="$ROOT/modules/site/commands/create.sh"
CREATE_LIB="$ROOT/modules/site/lib/create.sh"
PROVISION_LIB="$ROOT/modules/site/lib/provision.sh"
CREATE_ENV_DOC="$ROOT/modules/site/docs/CREATE-SITE-ENV-CONTRACT.md"
UI="$ROOT/modules/ui/menus/sites.sh"
HELP="$ROOT/modules/site/commands/help.sh"

for fn in site_purge site_purge_resolve_json site_purge_write_history site_purge_source_is_managed site_purge_legacy_nginx_matches_domain site_purge_nginx_remove; do
  grep -q "^${fn}()" "$F"
done

grep -q 'backup_verify' "$F"
grep -q 'down -v --remove-orphans' "$F"
grep -q -- '--force-active' "$F"
grep -q 'PURGE.ACTIVE_REQUIRES_FORCE' "$F"
grep -q 'PURGE.SOURCE_PATH_UNMANAGED' "$F"
grep -q 'PURGE.NGINX_FOREIGN_CONFIG' "$F"
grep -q '/opt/\$slug/repo' "$F"
grep -q '/opt/projects/\*' "$F"
grep -q 'www.\$domain' "$F"
grep -q 'Legacy Nginx config removed' "$F"

# Regression: destructive Nginx errors must not be hidden by >/dev/null 2>&1.
! grep -q 'platform_nginx_remove .*2>&1' "$F"

# Legacy config removal must still back up, validate and reload Nginx.
grep -q 'platform_nginx_backup_file' "$F"
grep -q 'nginx -t' "$F"
grep -q 'systemctl reload nginx' "$F"

# Purge backup policy: never start a stopped DB. Skip only when DB/container is
# genuinely absent; DB probe errors must abort rather than silently skip.
grep -q '^site_purge_database_backup_state()' "$POLICY"
grep -q 'skip:container-not-running' "$POLICY"
grep -q 'skip:database-not-found' "$POLICY"
grep -q 'PURGE.DB_PROBE_FAILED' "$POLICY"
grep -q 'backup_create_standard .*--no-database' "$POLICY"
! grep -q 'compose.*up.*db' "$POLICY"
grep -q 'modules/purge/lib/backup-policy.sh' "$CMD"

# P0 regression guard: Create Site must remain wired in CLI, UI and help.
grep -q '^site_create()' "$CREATE_LIB"
grep -q 'modules/site/lib/create.sh' "$CREATE_CMD"
grep -q 'platform_git_clone' "$CREATE_LIB"
grep -q 'site_provision_health' "$CREATE_LIB"
grep -q 'site_provision_commit_inventory' "$CREATE_LIB"
grep -q 'Create Site' "$UI"
grep -q 'ui_flow_create()' "$UI"
grep -q 'site create .*--name=' "$HELP"

# Docker env contract: Create/Provision must prefer .env.docker.example over
# .env.example, and the rule must be documented for future refactors/AI work.
grep -q '^site_provision_init_env()' "$PROVISION_LIB"
grep -q '\.env\.docker\.example' "$PROVISION_LIB"
grep -q 'fallback sang \.env\.example' "$PROVISION_LIB"
grep -q 'canonical / bắt buộc ưu tiên' "$CREATE_ENV_DOC"
grep -q '\.env\.docker\.example > \.env\.example' "$CREATE_ENV_DOC"

# Ensure docker template check appears before generic env fallback in provision.sh.
docker_line="$(grep -n 'if \[\[ -f "$project_path/\.env\.docker\.example"' "$PROVISION_LIB" | head -n1 | cut -d: -f1)"
fallback_line="$(grep -n 'if \[\[ -f "$project_path/\.env\.example"' "$PROVISION_LIB" | head -n1 | cut -d: -f1)"
[[ -n "$docker_line" && -n "$fallback_line" && "$docker_line" -lt "$fallback_line" ]]

grep -q 'Purge Force (active site)' "$UI"
grep -q 'ui_flow_purge_force()' "$UI"
grep -q 'site purge .*--force-active --yes' "$HELP"

bash -n "$F"
bash -n "$POLICY"
bash -n "$CMD"
bash -n "$CREATE_CMD"
bash -n "$CREATE_LIB"
bash -n "$PROVISION_LIB"
bash -n "$UI"
bash -n "$HELP"
echo "[OK] Site regression: create + docker-env-contract + purge-force + legacy-nginx + db-aware-backup"
