#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
SITE="$ROOT/modules/site/lib/site.sh"
PROV="$ROOT/modules/site/lib/provision.sh"
CREATE="$ROOT/modules/site/lib/create-strategy.sh"
CREATE_CMD="$ROOT/modules/site/commands/create.sh"
MENU="$ROOT/modules/ui/menus/sites.sh"
INVENTORY="$ROOT/modules/inventory/lib/inventory.sh"
COMMON="$ROOT/core/lib/common.sh"

[[ -f "$PROV" && -f "$CREATE" && -f "$COMMON" ]]
for fn in site_provision_configure_target site_provision_prepare_runtime site_provision_finalize_runtime site_provision_health site_provision_commit_inventory site_provision_cleanup_new_target; do
  grep -q "^${fn}()" "$PROV"
done
for fn in site_create_resolve_strategy site_create_validate_laravel site_create_repository_validate_contract site_create_repository_prepare site_create_repository_finalize site_create_repository_health site_create_repository_cleanup site_create; do
  grep -q "^${fn}()" "$CREATE"
done

grep -q 'create-strategy.sh' "$CREATE_CMD"
grep -q 'inventory_set_runtime_strategy' "$CREATE"
grep -q '^inventory_set_runtime_strategy()' "$INVENTORY"
grep -q 'Repository Compose service app không build từ Dockerfile' "$CREATE"
grep -q 'Repository web port không khớp HTTP_PORT' "$CREATE"
grep -q 'Không clone/build/start hoặc thay đổi Inventory' "$CREATE"
grep -q '4) Create site' "$MENU"
grep -q 'Docker theo repository' "$MENU"
grep -q 'Auto detect' "$MENU"
grep -q 'ui_flow_create' "$MENU"

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
source "$CREATE"
[[ "$(site_create_resolve_strategy platform "$tmp/platform" Dockerfile compose.yaml)" == "platform" ]]
[[ "$(site_create_resolve_strategy auto "$tmp/platform" Dockerfile compose.yaml)" == "platform" ]]
[[ "$(site_create_resolve_strategy auto "$tmp/repository" Dockerfile compose.yaml)" == "repository" ]]
[[ "$(site_create_resolve_strategy repository "$tmp/repository" Dockerfile compose.yaml)" == "repository" ]]

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

echo "[OK] Site Provisioning + Create Strategy tests"
