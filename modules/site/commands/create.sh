#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
source "$PLATFORM_HOME/modules/deploy/lib/deploy.sh"
source "$PLATFORM_HOME/modules/deploy/lib/readiness.sh"
source "$PLATFORM_HOME/modules/nginx/lib/nginx.sh"
source "$PLATFORM_HOME/modules/ssl/lib/ssl.sh"
source "$PLATFORM_HOME/modules/site/lib/site.sh"
source "$PLATFORM_HOME/modules/site/lib/repository.sh"
source "$PLATFORM_HOME/modules/site/lib/provision.sh"
source "$PLATFORM_HOME/modules/site/lib/create.sh"

has_repo=0
for arg in "$@"; do
  case "$arg" in
    --repo=*) has_repo=1 ;;
  esac
done

if [[ "$has_repo" -eq 0 ]]; then
  set -- "$@" "--repo=$(site_default_repo)"
fi

site_create "$@"
