#!/usr/bin/env bash

platform_help() {
  cat <<EOF
Laravel Deployment Platform $(cat "$VERSION_FILE" 2>/dev/null || echo dev)

USAGE
  platform <module> <command> [options]

MODULES
  site
  deploy
  database
  inventory
  ssl
  doctor
  plugin

CORE
  version
  help
  modules

EXAMPLES
  platform site list
  platform deploy run nvh
  platform inventory sync nvh
  platform database backup nvh
EOF
}

platform_dispatch() {
  local module="${1:-help}"
  shift || true

  case "$module" in
    help|-h|--help)
      platform_help
      ;;
    version|-v|--version)
      cat "$VERSION_FILE"
      ;;
    modules)
      module_list
      ;;
    *)
      module_dispatch "$module" "$@"
      ;;
  esac
}
