#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/nginx/lib/nginx.sh"
source "$PLATFORM_HOME/modules/ssl/lib/ssl.sh"
source "$PLATFORM_HOME/modules/site/lib/provision.sh"
source "$PLATFORM_HOME/modules/site/lib/site.sh"
source "$PLATFORM_HOME/modules/site/lib/domain-preflight.sh"
source "$PLATFORM_HOME/modules/site/lib/create-strategy.sh"
source "$PLATFORM_HOME/modules/site/lib/create-ssl-policy.sh"

create_name=""
create_domain=""
create_ssl=1
for arg in "$@"; do
  case "$arg" in
    --name=*) create_name="${arg#*=}" ;;
    --domain=*) create_domain="${arg#*=}" ;;
    --no-ssl) create_ssl=0 ;;
  esac
done

site_create "$@"

if [[ -n "$create_name" && -n "$create_domain" ]]; then
  site_create_record_ssl_status "$create_name" "$create_domain" "$create_ssl"
fi
