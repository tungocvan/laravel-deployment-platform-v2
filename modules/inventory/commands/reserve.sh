#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"

name=""
http_port=""

for arg in "$@"; do
  case "$arg" in
    --name=*) name="${arg#*=}" ;;
    --application=*|--domain=*|--path=*|--note=*) ;;
    --http-port=*) http_port="${arg#*=}" ;;
    *)
      platform_die \
        "$PLATFORM_EXIT_USAGE" \
        "INVENTORY.INVALID_OPTION" \
        "Option không hợp lệ: $arg"
      ;;
  esac
done

[[ -n "$name" ]] || platform_die \
  "$PLATFORM_EXIT_USAGE" \
  "INVENTORY.ARGUMENT_REQUIRED" \
  "Thiếu --name"

[[ "$http_port" =~ ^[0-9]+$ ]] || platform_die \
  "$PLATFORM_EXIT_VALIDATION" \
  "INVENTORY.INVALID_PORT" \
  "--http-port phải là số"

((http_port >= 1 && http_port <= 65535)) || platform_die \
  "$PLATFORM_EXIT_VALIDATION" \
  "INVENTORY.INVALID_PORT" \
  "Port không hợp lệ"

inventory_reserve "$@"
