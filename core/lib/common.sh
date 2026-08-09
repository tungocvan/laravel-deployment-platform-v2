#!/usr/bin/env bash

# Platform 2.1 coarse process exit classes.
# Keep legacy die() at exit 1 until callers are migrated intentionally.
readonly PLATFORM_EXIT_OK=0
readonly PLATFORM_EXIT_USAGE=2
readonly PLATFORM_EXIT_VALIDATION=3
readonly PLATFORM_EXIT_DEPENDENCY=4
readonly PLATFORM_EXIT_CONFLICT=5
readonly PLATFORM_EXIT_OPERATION=6
readonly PLATFORM_EXIT_HEALTH=7
readonly PLATFORM_EXIT_ROLLBACK=8
readonly PLATFORM_EXIT_INTERNAL=9

info()    { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn()    { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()     { error "$*"; exit 1; }

platform_error() {
  local error_id="${1:-CORE.INTERNAL_ERROR}"
  shift || true
  printf '\033[1;31m[ERROR]\033[0m [%s] %s\n' "$error_id" "$*" >&2
}

platform_die() {
  local exit_code="${1:-$PLATFORM_EXIT_INTERNAL}"
  local error_id="${2:-CORE.INTERNAL_ERROR}"
  shift 2 || true

  platform_error "$error_id" "$*"
  exit "$exit_code"
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || platform_die \
    "$PLATFORM_EXIT_DEPENDENCY" \
    "CORE.ROOT_REQUIRED" \
    "Command này cần sudo/root."
}

require_command() {
  local required_command="${1:-}"

  command -v "$required_command" >/dev/null 2>&1 || platform_die \
    "$PLATFORM_EXIT_DEPENDENCY" \
    "CORE.REQUIRED_COMMAND_MISSING" \
    "Thiếu command: $required_command"
}

confirm() {
  local answer
  read -r -p "${1:-Tiếp tục?} [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
