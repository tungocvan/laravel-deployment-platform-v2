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

# Existing success paths remain unchanged.
"$PLATFORM_HOME/bin/platform" version >/dev/null
"$PLATFORM_HOME/bin/platform" modules | grep -qx site
"$PLATFORM_HOME/bin/platform" modules | grep -qx deploy

# Platform 2.1 dispatcher failures expose a stable identifier and USAGE exit class.
assert_dispatch_error 2 CORE.MODULE_NOT_FOUND __platform_2_1_missing_module__
assert_dispatch_error 2 CORE.COMMAND_NOT_FOUND site __platform_2_1_missing_command__

echo "[OK] core tests"
