#!/usr/bin/env bash

module_dir() {
  printf '%s/modules/%s' "$PLATFORM_HOME" "$1"
}

module_exists() {
  [[ -d "$(module_dir "$1")" ]]
}

module_list() {
  find "$PLATFORM_HOME/modules" -mindepth 1 -maxdepth 1 -type d \
    -printf '%f\n' | sort
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

  # Prevent path traversal and keep dispatch limited to command file names.
  [[ "$command" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ || "$command" =~ ^(-h|--help)$ ]] || platform_die \
    "$PLATFORM_EXIT_USAGE" \
    "CORE.COMMAND_NOT_FOUND" \
    "Command không tồn tại: platform $module $command"

  local handler
  handler="$(module_dir "$module")/commands/${command}.sh"

  if [[ "$command" =~ ^(-h|--help|help)$ ]]; then
    handler="$(module_dir "$module")/commands/help.sh"
  fi

  [[ -f "$handler" ]] || platform_die \
    "$PLATFORM_EXIT_USAGE" \
    "CORE.COMMAND_NOT_FOUND" \
    "Command không tồn tại: platform $module $command"

  # Execute through bash so a valid tracked command still works if its executable
  # bit is lost by an archive, filesystem, or repository contents API.
  exec bash "$handler" "$@"
}
