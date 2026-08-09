#!/usr/bin/env bash

# Platform 2.1 in-process transaction mechanics.
# Business ordering and user-visible error semantics remain module-owned.

PLATFORM_TX_IS_ACTIVE=0
PLATFORM_TX_CURRENT_NAME=""
PLATFORM_TX_FAILED_ROLLBACKS=0
PLATFORM_TX_ROLLBACK_FN=()
PLATFORM_TX_ROLLBACK_ARG_START=()
PLATFORM_TX_ROLLBACK_ARG_COUNT=()
PLATFORM_TX_ROLLBACK_ARGS=()

platform_tx_active() {
  [[ "$PLATFORM_TX_IS_ACTIVE" -eq 1 ]]
}

platform_tx_name() {
  printf '%s' "$PLATFORM_TX_CURRENT_NAME"
}

platform_tx_rollback_failures() {
  printf '%s' "$PLATFORM_TX_FAILED_ROLLBACKS"
}

platform_tx_cleanup() {
  PLATFORM_TX_IS_ACTIVE=0
  PLATFORM_TX_CURRENT_NAME=""
  PLATFORM_TX_FAILED_ROLLBACKS=0
  PLATFORM_TX_ROLLBACK_FN=()
  PLATFORM_TX_ROLLBACK_ARG_START=()
  PLATFORM_TX_ROLLBACK_ARG_COUNT=()
  PLATFORM_TX_ROLLBACK_ARGS=()
}

platform_tx_begin() {
  local name="${1:-}"
  [[ -n "$name" ]] || return 1
  platform_tx_active && return 1

  platform_tx_cleanup
  PLATFORM_TX_IS_ACTIVE=1
  PLATFORM_TX_CURRENT_NAME="$name"
}

platform_tx_register() {
  platform_tx_active || return 1

  local callback="${1:-}"
  [[ -n "$callback" ]] || return 1
  declare -F "$callback" >/dev/null 2>&1 || return 1
  shift || true

  local start=${#PLATFORM_TX_ROLLBACK_ARGS[@]}
  local count=$#

  PLATFORM_TX_ROLLBACK_FN+=("$callback")
  PLATFORM_TX_ROLLBACK_ARG_START+=("$start")
  PLATFORM_TX_ROLLBACK_ARG_COUNT+=("$count")
  if (( count > 0 )); then
    PLATFORM_TX_ROLLBACK_ARGS+=("$@")
  fi
}

platform_tx_commit() {
  platform_tx_active || return 1
  platform_tx_cleanup
}

platform_tx_rollback() {
  platform_tx_active || return 1

  local failures=0
  local i callback start count rc

  for ((i=${#PLATFORM_TX_ROLLBACK_FN[@]}-1; i>=0; i--)); do
    callback="${PLATFORM_TX_ROLLBACK_FN[$i]}"
    start="${PLATFORM_TX_ROLLBACK_ARG_START[$i]}"
    count="${PLATFORM_TX_ROLLBACK_ARG_COUNT[$i]}"

    set +e
    if (( count > 0 )); then
      "$callback" "${PLATFORM_TX_ROLLBACK_ARGS[@]:start:count}"
    else
      "$callback"
    fi
    rc=$?
    set -e

    if [[ "$rc" -ne 0 ]]; then
      failures=$((failures + 1))
    fi
  done

  PLATFORM_TX_FAILED_ROLLBACKS="$failures"
  PLATFORM_TX_IS_ACTIVE=0
  PLATFORM_TX_CURRENT_NAME=""
  PLATFORM_TX_ROLLBACK_FN=()
  PLATFORM_TX_ROLLBACK_ARG_START=()
  PLATFORM_TX_ROLLBACK_ARG_COUNT=()
  PLATFORM_TX_ROLLBACK_ARGS=()

  [[ "$failures" -eq 0 ]]
}
