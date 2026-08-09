#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
SITE="$ROOT/modules/site/lib/site.sh"
PROV="$ROOT/modules/site/lib/provision.sh"
CREATE="$ROOT/modules/site/lib/create-strategy.sh"
DOMAIN="$ROOT/modules/site/lib/domain-preflight.sh"
SSL_POLICY="$ROOT/modules/site/lib/create-ssl-policy.sh"
DOMAIN_CMD="$ROOT/modules/site/commands/domain-preflight.sh"
CREATE_CMD="$ROOT/modules/site/commands/create.sh"
MENU="$ROOT/modules/ui/menus/sites.sh"
INVENTORY="$ROOT/modules/inventory/lib/inventory.sh"
COMMON="$ROOT/core/lib/common.sh"

[[ -f "$PROV" && -f "$CREATE" && -f "$DOMAIN" && -f "$SSL_POLICY" && -f "$DOMAIN_CMD" && -f "$COMMON" ]]
for fn in site_provision_configure_target site_provision_prepare_runtime site_provision_finalize_runtime site_provision_health site_provision_commit_inventory site_provision_cleanup_new_target; do
  grep -q "^${fn}()" "$PROV"
done
for fn in site_create_resolve_strategy site_create_validate_laravel site_create_repository_validate_contract site_create_repository_prepare site_create_repository_finalize site_create_repository_health site_create_repository_cleanup site_create_domain_gate site_create; do
  grep -q "^${fn}()" "$CREATE"
done
for fn in site_domain_ipv4_local site_domain_ipv6_local site_domain_dns_ipv4 site_domain_dns_ipv6 site_domain_all_in_set site_domain_preflight; do
  grep -q "^${fn}()" "$DOMAIN"
done
for fn in platform_ssl_issue site_create_record_ssl_status; do
  grep -q "^${fn}()" "$SSL_POLICY"
done

grep -q 'domain-preflight.sh' "$CREATE_CMD"
grep -q 'create-ssl-policy.sh' "$CREATE_CMD"
grep -q 'site_create_record_ssl_status' "$CREATE_CMD"
grep -q 'site_domain_preflight' "$DOMAIN_CMD"
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
grep -q 'Docker theo repository' "$MENU"
grep -q 'Auto detect' "$MENU"
grep -q 'ui_flow_create' "$MENU"
grep -q "grep -vi '^::ffff:'" "$DOMAIN"

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

echo "[OK] Site Provisioning + Create Strategy + Domain Preflight + SSL Policy tests"
