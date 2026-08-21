#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"
SITE="$ROOT/modules/site/lib/site.sh"
PROV="$ROOT/modules/site/lib/provision.sh"
REPO_LIB="$ROOT/modules/site/lib/repository.sh"
CREATE_CMD="$ROOT/modules/site/commands/create.sh"
HELP_CMD="$ROOT/modules/site/commands/help.sh"

[[ -f "$PROV" ]]
[[ -f "$REPO_LIB" ]]
for fn in \
  site_provision_configure_target \
  site_provision_prepare_runtime \
  site_provision_finalize_runtime \
  site_provision_health \
  site_provision_commit_inventory \
  site_provision_cleanup_new_target
do
  grep -q "^${fn}()" "$PROV"
done

grep -q 'site_provision_configure_target' "$SITE"
grep -q 'site_provision_prepare_runtime' "$SITE"
grep -q 'platform_ssl_issue' "$SITE"

# Canonical repository contract shared by CLI/UI.
# shellcheck disable=SC1090
source "$REPO_LIB"
[[ "$(site_canonical_repo)" == 'git@github.com:tungocvan/laravel-shop.git' ]]
[[ "$(site_default_repo)" == 'git@github.com:tungocvan/laravel-shop.git' ]]
PLATFORM_DEFAULT_SITE_REPO='git@example.test:custom/app.git'
[[ "$(site_default_repo)" == 'git@example.test:custom/app.git' ]]
unset PLATFORM_DEFAULT_SITE_REPO

grep -q 'site_default_repo' "$CREATE_CMD"
grep -q 'default: git@github.com:tungocvan/laravel-shop.git' "$HELP_CMD"
grep -q '^PLATFORM_HOME=/opt/laravel-deployment-platform-v2$' "$ROOT/config/platform.env.example"
grep -q '^INVENTORY_FILE=/opt/laravel-deployment-platform-v2/state/sites.json$' "$ROOT/config/platform.env.example"
grep -q '^PLATFORM_DEFAULT_SITE_REPO=git@github.com:tungocvan/laravel-shop.git$' "$ROOT/config/platform.env.example"
grep -q 'PLATFORM_HOME="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"' "$ROOT/core/bootstrap.sh"

# Platform v2 runtime code/config must not fall back to the legacy v1 install path.
if grep -RFn '/opt/laravel-deployment-platform/' \
  "$ROOT/core" "$ROOT/config" "$ROOT/modules" \
  --exclude='test-site.sh' >/tmp/platform-v2-legacy-paths.$$ 2>/dev/null; then
  echo '[ERROR] Legacy Platform v1 runtime path detected:'
  cat /tmp/platform-v2-legacy-paths.$$
  rm -f /tmp/platform-v2-legacy-paths.$$
  exit 1
fi
rm -f /tmp/platform-v2-legacy-paths.$$

if grep -q 'certbot ' "$SITE"; then
  echo "[ERROR] Site Module không được gọi Certbot trực tiếp."
  exit 1
fi

echo "[OK] Site Provisioning Engine + canonical repository contract + v2 paths"
