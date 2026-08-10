#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for module in "$ROOT"/modules/*; do
  [[ -d "$module" ]] || continue

  # Library-only/internal modules (for example lifecycle) are valid and do not
  # expose CLI commands. Only dispatchable modules with commands/ must provide
  # an executable help command.
  [[ -d "$module/commands" ]] || continue

  [[ -x "$module/commands/help.sh" ]] || {
    echo "[ERROR] Missing help.sh: $module"
    exit 1
  }
done

# Site update storage overlay must only detect Git-managed additions/modifications
# below storage/app/public. Runtime uploads outside Git remain untouched.
source "$ROOT/modules/site/lib/update.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "platform-test@example.invalid"
git -C "$repo" config user.name "Platform Test"
mkdir -p "$repo/storage/app/public" "$repo/app"
printf 'old\n' > "$repo/storage/app/public/logo.png"
printf 'code-v1\n' > "$repo/app/example.php"
git -C "$repo" add .
git -C "$repo" commit -qm "initial"
old_commit="$(git -C "$repo" rev-parse HEAD)"
printf 'new\n' > "$repo/storage/app/public/logo.png"
printf 'code-v2\n' > "$repo/app/example.php"
printf 'runtime-only\n' > "$repo/storage/app/public/runtime-upload.png"
git -C "$repo" add storage/app/public/logo.png app/example.php
git -C "$repo" commit -qm "update"
new_commit="$(git -C "$repo" rev-parse HEAD)"

changes="$(site_update_storage_changed_files "$repo" "$old_commit" "$new_commit")"
[[ "$changes" == "storage/app/public/logo.png" ]] || {
  echo "[ERROR] Git-managed storage detection không đúng: $changes"
  exit 1
}

if grep -q 'runtime-upload.png' <<<"$changes"; then
  echo "[ERROR] Runtime upload không được đưa vào Git storage sync."
  exit 1
fi

if grep -q 'app/example.php' <<<"$changes"; then
  echo "[ERROR] Source code ngoài storage/app/public không được đưa vào storage sync."
  exit 1
fi

# Managed change-domain contract: stage new domain first, ensure the certificate
# is actually deployed into Nginx, refresh APP_URL/runtime, update Inventory trace,
# then remove only the old managed Nginx config.
CHANGE="$ROOT/modules/site/lib/change-domain.sh"
CHANGE_CMD="$ROOT/modules/site/commands/change-domain.sh"
MENU="$ROOT/modules/ui/menus/sites.sh"
HELP="$ROOT/modules/site/commands/help.sh"
SSL_LIB="$ROOT/modules/ssl/lib/ssl.sh"
PROVISION="$ROOT/modules/site/lib/provision.sh"

[[ -f "$CHANGE" && -f "$CHANGE_CMD" && -f "$SSL_LIB" ]]
for fn in site_change_domain_record_inventory site_change_domain_refresh_app site_change_domain_gate site_change_domain; do
  grep -q "^${fn}()" "$CHANGE"
done
for fn in platform_ssl_nginx_deployed platform_ssl_install_existing platform_ssl_ensure; do
  grep -q "^${fn}()" "$SSL_LIB"
done
grep -q 'certbot install' "$SSL_LIB"
grep -q -- '--cert-name "\$domain"' "$SSL_LIB"
grep -q 'platform_ssl_nginx_deployed "\$domain"' "$SSL_LIB"
grep -q 'platform_nginx_ensure_proxy "\$new_domain"' "$CHANGE"
grep -q 'platform_ssl_ensure "\$new_domain"' "$CHANGE"
grep -q 'platform_ssl_ensure "\$domain"' "$PROVISION"
grep -q 'APP_URL "\$new_app_url"' "$CHANGE"
grep -q 'previous_domain' "$CHANGE"
grep -q 'platform_nginx_remove "\$old_domain"' "$CHANGE"
grep -q 'Certificate cũ' "$CHANGE"
grep -q 'site_change_domain "\$@"' "$CHANGE_CMD"
grep -q '6) Change domain' "$MENU"
grep -q 'ui_flow_change_domain' "$MENU"
grep -q 'site change-domain "\$site"' "$MENU"
grep -q 'change-domain <site>' "$HELP"

# Change-domain must not run migrations or database seeding.
if grep -Eq 'artisan[[:space:]]+(migrate|db:seed)' "$CHANGE"; then
  echo "[ERROR] Change-domain không được migrate hoặc db:seed."
  exit 1
fi

echo "[OK] module tests"
