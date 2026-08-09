#!/usr/bin/env bash

module_dir() {
  printf '%s/modules/%s' "$PLATFORM_HOME" "$1"
}

module_exists() {
  [[ -d "$(module_dir "$1")" ]]
}

module_list() {
  find "$PLATFORM_HOME/modules" -mindepth 1 -maxdepth 1 -type d     -printf '%f\n' | sort
}

module_dispatch() {
  local module="$1"
  shift || true
  local command="${1:-help}"
  shift || true

  module_exists "$module" || platform_die \
    "$PLATFORM_EXIT_USAGE" \
    "CORE.MODULE_NOT_FOUND" \
    "Module không tồn tại: $module"

  local handler
  handler="$(module_dir "$module")/commands/${command}.sh"

  if [[ "$command" =~ ^(-h|--help|help)$ ]]; then
    handler="$(module_dir "$module")/commands/help.sh"
  fi

  [[ -x "$handler" ]] || platform_die \
    "$PLATFORM_EXIT_USAGE" \
    "CORE.COMMAND_NOT_FOUND" \
    "Command không tồn tại: platform $module $command"

  exec "$handler" "$@"
}
