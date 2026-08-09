#!/usr/bin/env bash
set -Eeuo pipefail

export PLATFORM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_dispatch_error() {
  local expected_exit="$1"
  local expected_error_id="$2"
  shift 2

  local output status
  set +e
  output="$("$PLATFORM_HOME/bin/platform" "$@" 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne "$expected_exit" ]]; then
    printf '[FAIL] expected exit %s, got %s for: platform %s\n' \
      "$expected_exit" "$status" "$*" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  if [[ "$output" != *"[$expected_error_id]"* ]]; then
    printf '[FAIL] missing error id %s for: platform %s\n' \
      "$expected_error_id" "$*" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

assert_common_error() {
  local expected_exit="$1"
  local expected_error_id="$2"
  local scenario="$3"

  local output status
  set +e
  output="$(PLATFORM_HOME="$PLATFORM_HOME" bash -c '
    source "$PLATFORM_HOME/core/lib/common.sh"
    case "$1" in
      missing-command)
        require_command __platform_2_1_missing_binary__
        ;;
      root-required)
        platform_current_uid() { printf "1000"; }
        require_root
        ;;
      *)
        exit 99
        ;;
    esac
  ' _ "$scenario" 2>&1)"
  status=$?
  set -e

  if [[ "$status" -ne "$expected_exit" ]]; then
    printf '[FAIL] expected exit %s, got %s for common scenario: %s\n' \
      "$expected_exit" "$status" "$scenario" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi

  if [[ "$output" != *"[$expected_error_id]"* ]]; then
    printf '[FAIL] missing error id %s for common scenario: %s\n' \
      "$expected_error_id" "$scenario" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

# Existing success paths remain unchanged.
"$PLATFORM_HOME/bin/platform" version >/dev/null
"$PLATFORM_HOME/bin/platform" modules | grep -qx site
"$PLATFORM_HOME/bin/platform" modules | grep -qx deploy

# Platform 2.1 dispatcher failures expose a stable identifier and USAGE exit class.
assert_dispatch_error 2 CORE.MODULE_NOT_FOUND __platform_2_1_missing_module__
assert_dispatch_error 2 CORE.COMMAND_NOT_FOUND site __platform_2_1_missing_command__

# Shared dependency/precondition helpers expose stable identifiers and DEPENDENCY exit class.
assert_common_error 4 CORE.REQUIRED_COMMAND_MISSING missing-command
assert_common_error 4 CORE.ROOT_REQUIRED root-required

# Success behavior for shared helpers remains unchanged.
PLATFORM_HOME="$PLATFORM_HOME" bash -c \
  'source "$PLATFORM_HOME/core/lib/common.sh"; require_command bash'
PLATFORM_HOME="$PLATFORM_HOME" bash -c \
  'source "$PLATFORM_HOME/core/lib/common.sh"; platform_current_uid() { printf "0"; }; require_root'

echo "[OK] core tests"
