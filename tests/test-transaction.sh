#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/core/lib/transaction.sh"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

TRACE="$(mktemp)"
trap 'rm -f "$TRACE"' EXIT

record_action() {
  printf '%s|%s\n' "$1" "${2:-}" >> "$TRACE"
}

failing_action() {
  printf '%s\n' "$1" >> "$TRACE"
  return 7
}

platform_tx_active && fail "transaction unexpectedly active initially"

platform_tx_begin alpha || fail "begin failed"
platform_tx_active || fail "transaction should be active"
[[ "$(platform_tx_name)" == "alpha" ]] || fail "transaction name mismatch"
if platform_tx_begin nested; then
  fail "nested transaction should be rejected"
fi

platform_tx_register record_action first "arg with spaces" || fail "register first failed"
platform_tx_register record_action second "two" || fail "register second failed"
platform_tx_rollback || fail "rollback should succeed"

EXPECTED=$'second|two\nfirst|arg with spaces'
[[ "$(cat "$TRACE")" == "$EXPECTED" ]] || fail "rollback order/arguments mismatch"
[[ "$(platform_tx_rollback_failures)" == "0" ]] || fail "unexpected rollback failure count"
platform_tx_active && fail "transaction should be inactive after rollback"

: > "$TRACE"
platform_tx_begin failure-case || fail "failure-case begin failed"
platform_tx_register record_action first "ok" || fail "register first success failed"
platform_tx_register failing_action failing || fail "register failing action failed"
platform_tx_register record_action last "ok" || fail "register last success failed"

if platform_tx_rollback; then
  fail "rollback with failing callback should return non-zero"
fi

EXPECTED=$'last|ok\nfailing\nfirst|ok'
[[ "$(cat "$TRACE")" == "$EXPECTED" ]] || fail "rollback did not continue after failure"
[[ "$(platform_tx_rollback_failures)" == "1" ]] || fail "rollback failure count mismatch"
platform_tx_active && fail "failed rollback should still close transaction"

: > "$TRACE"
platform_tx_begin commit-case || fail "commit-case begin failed"
platform_tx_register record_action should-not-run "commit" || fail "commit register failed"
platform_tx_commit || fail "commit failed"
platform_tx_active && fail "transaction should be inactive after commit"
if platform_tx_rollback; then
  fail "rollback should reject inactive transaction"
fi
[[ ! -s "$TRACE" ]] || fail "commit must discard rollback actions"

platform_tx_cleanup
platform_tx_cleanup
platform_tx_active && fail "cleanup should be idempotent and inactive"
[[ -z "$(platform_tx_name)" ]] || fail "cleanup should clear transaction name"
[[ "$(platform_tx_rollback_failures)" == "0" ]] || fail "cleanup should reset rollback failures"

if platform_tx_register record_action invalid; then
  fail "register should reject inactive transaction"
fi

platform_tx_begin callback-validation || fail "callback-validation begin failed"
if platform_tx_register __platform_missing_callback__; then
  fail "register should reject unknown callback"
fi
platform_tx_cleanup

echo "[OK] transaction tests"
