#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
SITE="$ROOT/modules/site/lib/site.sh"
PROV="$ROOT/modules/site/lib/provision.sh"
CREATE="$ROOT/modules/site/lib/create-strategy.sh"
UPDATE="$ROOT/modules/site/lib/update.sh"
ENV_LIB="$ROOT/modules/site/lib/env.sh"
STORAGE_LIB="$ROOT/modules/site/lib/storage.sh"
DOMAIN="$ROOT/modules/site/lib/domain-preflight.sh"
SSL_POLICY="$ROOT/modules/site/lib/create-ssl-policy.sh"
SEED_POLICY="$ROOT/modules/site/lib/create-seed-policy.sh"
DOMAIN_CMD="$ROOT/modules/site/commands/domain-preflight.sh"
CREATE_CMD="$ROOT/modules/site/commands/create.sh"
UPDATE_CMD="$ROOT/modules/site/commands/update.sh"
ENV_CMD="$ROOT/modules/site/commands/env.sh"
STORAGE_CMD="$ROOT/modules/site/commands/storage.sh"
MENU="$ROOT/modules/ui/menus/sites.sh"
INVENTORY="$ROOT/modules/inventory/lib/inventory.sh"
COMMON="$ROOT/core/lib/common.sh"

[[ -f "$PROV" && -f "$CREATE" && -f "$UPDATE" && -f "$ENV_LIB" && -f "$STORAGE_LIB" && -f "$DOMAIN" && -f "$SSL_POLICY" && -f "$SEED_POLICY" && -f "$DOMAIN_CMD" && -f "$UPDATE_CMD" && -f "$ENV_CMD" && -f "$STORAGE_CMD" && -f "$COMMON" ]]
for fn in site_provision_configure_target site_provision_prepare_runtime site_provision_finalize_runtime site_provision_health site_provision_commit_inventory site_provision_cleanup_new_target; do
  grep -q "^${fn}()" "$PROV"
done
for fn in site_create_resolve_strategy site_create_validate_laravel site_create_repository_validate_contract site_create_repository_prepare site_create_repository_finalize site_create_repository_health site_create_repository_cleanup site_create_domain_gate site_create; do
  grep -q "^${fn}()" "$CREATE"
done
for fn in site_update_local_changes site_update_record_commit site_update_deploy site_update; do
  grep -q "^${fn}()" "$UPDATE"
done
for fn in site_env_context site_env_get site_env_backup site_env_write_value site_env_refresh site_env_set site_env_command; do
  grep -q "^${fn}()" "$ENV_LIB"
done
for fn in site_storage_context site_storage_compose site_storage_status site_storage_repair site_storage_list site_storage_put site_storage_command; do
  grep -q "^${fn}()" "$STORAGE_LIB"
done
for fn in site_domain_ipv4_local site_domain_ipv6_local site_domain_dns_ipv4 site_domain_dns_ipv6 site_domain_all_in_set site_domain_preflight; do
  grep -q "^${fn}()" "$DOMAIN"
done
for fn in platform_ssl_issue site_create_record_ssl_status; do
  grep -q "^${fn}()" "$SSL_POLICY"
done
for fn in site_create_seed_repository site_create_seed_platform site_create_repository_finalize site_provision_finalize_runtime; do
  grep -q "^${fn}()" "$SEED_POLICY"
done

grep -q 'domain-preflight.sh' "$CREATE_CMD"
grep -q 'create-ssl-policy.sh' "$CREATE_CMD"
grep -q 'create-seed-policy.sh' "$CREATE_CMD"
grep -q 'site_create_record_ssl_status' "$CREATE_CMD"
grep -q 'site_domain_preflight' "$DOMAIN_CMD"
grep -q 'site/lib/update.sh' "$UPDATE_CMD"
grep -q 'site_update "\$@"' "$UPDATE_CMD"
grep -q 'site/lib/env.sh' "$ENV_CMD"
grep -q 'site_env_command "\$@"' "$ENV_CMD"
grep -q 'site/lib/storage.sh' "$STORAGE_CMD"
grep -q 'site_storage_command "\$@"' "$STORAGE_CMD"
grep -q 'inventory_set_runtime_strategy' "$CREATE"
grep -q '^inventory_set_runtime_strategy()' "$INVENTORY"
grep -q 'Repository Compose service app không build từ Dockerfile' "$CREATE"
grep -q 'Repository web port không khớp HTTP_PORT' "$CREATE"
grep -q 'Không clone/build/start hoặc thay đổi Inventory' "$CREATE"
grep -q -- '--replace-domain-config' "$CREATE"
grep -q 'DOMAIN / SSL PREFLIGHT' "$MENU"
grep -q 'Làm mới config' "$MENU"
grep -q 'Tạo site KHÔNG SSL' "$MENU"
grep -q '4) Create site' "$MENU"
grep -q '5) Update site from GitHub' "$MENU"
grep -q '17) Environment (.env)' "$MENU"
grep -q '18) Storage' "$MENU"
grep -q 'ui_flow_env' "$MENU"
grep -q 'ui_flow_storage' "$MENU"
grep -q 'site env "\$site"' "$MENU"
grep -q 'site storage "\$site"' "$MENU"
grep -q 'ui_flow_update' "$MENU"
grep -q 'site update "\$site" --dry-run' "$MENU"
grep -q 'Docker theo repository' "$MENU"
grep -q 'Auto detect' "$MENU"
grep -q 'ui_flow_create' "$MENU"
grep -q "grep -vi '^::ffff:'" "$DOMAIN"

# Environment/storage safety contracts.
grep -q 'chmod 600' "$ENV_LIB"
grep -q '.platform-backups/env' "$ENV_LIB"
grep -q 'os.replace(tmp,path)' "$ENV_LIB"
grep -q 'up -d --force-recreate app queue scheduler socket' "$ENV_LIB"
if grep -Eq 'cat[[:space:]]+.*\.env|print.*\.env' "$ENV_LIB"; then
  echo "[ERROR] Env management không được có command dump toàn bộ .env."
  exit 1
fi
grep -q 'public/storage' "$STORAGE_LIB"
grep -q 'chown -R www-data:www-data storage bootstrap/cache' "$STORAGE_LIB"
grep -q 'Storage path không được chứa' "$STORAGE_LIB"
if grep -Eq 'rm -rf[[:space:]]+storage|docker compose.*down -v' "$STORAGE_LIB"; then
  echo "[ERROR] Storage management không được phá hủy persistent storage."
  exit 1
fi

# Update contract: create-only seed policy must not be sourced by update command.
if grep -q 'create-seed-policy.sh' "$UPDATE_CMD"; then
  echo "[ERROR] Site update không được source create seed policy."
  exit 1
fi
grep -q 'site_create_repository_finalize' "$UPDATE"
grep -q 'deploy_run' "$UPDATE"
grep -q 'status --porcelain --untracked-files=no' "$UPDATE"
grep -q 'merge-base --is-ancestor' "$UPDATE"
grep -q 'reset --hard "origin/\$branch"' "$UPDATE"
grep -q 'GitHub origin/\$branch là source of truth' "$UPDATE"
grep -q 'Local tracked changes sẽ bị loại bỏ' "$UPDATE"
grep -q 'previous_commit' "$UPDATE"
grep -q 'last_updated_at' "$UPDATE"
grep -q 'Không tự git reset rollback' "$UPDATE"
if grep -q 'merge --ff-only' "$UPDATE"; then
  echo "[ERROR] Managed production update phải reset chính xác về origin/branch, không merge local changes."
  exit 1
fi

# Normal deploy must remain seed-free.
if grep -q 'db:seed' "$ROOT/modules/deploy/lib/deploy.sh"; then
  echo "[ERROR] Deploy thường không được tự chạy db:seed."
  exit 1
fi

grep -q 'site_provision_configure_target' "$SITE"
grep -q 'site_provision_prepare_runtime' "$SITE"
grep -q 'platform_ssl_issue' "$SITE"
if grep -q 'certbot ' "$SITE"; then
  echo "[ERROR] Site Module không được gọi Certbot trực tiếp."
  exit 1
fi

# Deterministic strategy resolution without Docker/network mutation.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/platform" "$tmp/repository"
touch "$tmp/repository/Dockerfile" "$tmp/repository/compose.yaml"

source "$COMMON"
source "$DOMAIN"
source "$CREATE"
[[ "$(site_create_resolve_strategy platform "$tmp/platform" Dockerfile compose.yaml)" == "platform" ]]
[[ "$(site_create_resolve_strategy auto "$tmp/platform" Dockerfile compose.yaml)" == "platform" ]]
[[ "$(site_create_resolve_strategy auto "$tmp/repository" Dockerfile compose.yaml)" == "repository" ]]
[[ "$(site_create_resolve_strategy repository "$tmp/repository" Dockerfile compose.yaml)" == "repository" ]]

site_domain_all_in_set $'157.10.198.16\n10.0.0.1' $'10.0.0.1\n157.10.198.16'
if site_domain_all_in_set $'157.10.198.16\n1.2.3.4' $'10.0.0.1\n157.10.198.16'; then
  echo "[ERROR] DNS set mismatch phải fail."
  exit 1
fi

# IPv4-mapped IPv6 (::ffff:a.b.c.d) is not a real AAAA record for SSL routing.
TEST_GETENT_DIR="$tmp/getent-bin"
mkdir -p "$TEST_GETENT_DIR"
cat > "$TEST_GETENT_DIR/getent" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  ahostsv6)
    printf '%s\n' '::ffff:157.10.198.16 STREAM example.test' '::ffff:157.10.198.16 DGRAM example.test'
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$TEST_GETENT_DIR/getent"
actual_dns6="$(PATH="$TEST_GETENT_DIR:$PATH" site_domain_dns_ipv6 example.test)"
[[ -z "$actual_dns6" ]] || {
  echo "[ERROR] IPv4-mapped IPv6 phải bị loại khỏi DNS IPv6 preflight: $actual_dns6"
  exit 1
}

# Create Site must seed after migrate and before optimize for repository strategy.
TEST_SEED_POLICY="$SEED_POLICY" bash -c '
  set -Eeuo pipefail
  calls=""
  warn(){ :; }
  site_create_repository_compose(){
    case "$*" in
      *"php artisan migrate --force"*) calls+=$'"'"'migrate\n'"'"' ;;
      *"php artisan db:seed --force"*) calls+=$'"'"'seed\n'"'"' ;;
      *"php artisan optimize:clear"*) calls+=$'"'"'optimize\n'"'"' ;;
      *) : ;;
    esac
  }
  source "$TEST_SEED_POLICY"
  site_create_repository_finalize /tmp/site compose.yaml
  [[ "$calls" == $'"'"'migrate\nseed\noptimize\n'"'"' ]]
'

# Create Site must seed after migrate and before optimize for platform strategy.
TEST_SEED_POLICY="$SEED_POLICY" bash -c '
  set -Eeuo pipefail
  calls=""
  deploy_migrate_path(){ calls+=$'"'"'migrate\n'"'"'; }
  deploy_compose(){ calls+=$'"'"'seed\n'"'"'; }
  deploy_optimize_path(){ calls+=$'"'"'optimize\n'"'"'; }
  deploy_health_path(){ calls+=$'"'"'health\n'"'"'; }
  source "$TEST_SEED_POLICY"
  site_provision_finalize_runtime /tmp/site
  [[ "$calls" == $'"'"'migrate\nseed\noptimize\nhealth\n'"'"' ]]
'

# Create Site must keep the HTTP site when Certbot fails.
TEST_SSL_POLICY="$SSL_POLICY" bash -c '
  set -Eeuo pipefail
  require_root(){ :; }
  platform_ssl_require(){ :; }
  platform_ssl_validate_domain(){ :; }
  platform_nginx_conflict_files(){ :; }
  certbot(){ return 1; }
  platform_ssl_verify(){ return 1; }
  warn(){ :; }
  success(){ :; }
  source "$TEST_SSL_POLICY"
  platform_ssl_issue example.test
'

set +e
PLATFORM_HOME="$ROOT" TEST_CREATE="$CREATE" TEST_COMMON="$COMMON" TEST_PATH="$tmp/platform" bash -c '
  set -Eeuo pipefail
  source "$TEST_COMMON"
  source "$TEST_CREATE"
  site_create_resolve_strategy repository "$TEST_PATH" Dockerfile compose.yaml >/dev/null
'
missing_contract_rc=$?
set -e
[[ "$missing_contract_rc" -ne 0 ]] || {
  echo "[ERROR] repository strategy phải fail khi thiếu Docker contract."
  exit 1
}

echo "[OK] Site Provisioning + Create Strategy + Domain Preflight + Seed + SSL Policy + Update + Env + Storage tests"
