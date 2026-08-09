#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLATFORM_HOME="$ROOT"
source "$ROOT/core/bootstrap.sh"
source "$ROOT/core/lib/package.sh"
source "$ROOT/modules/package/lib/package.sh"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

TMP_ROOT="$(mktemp -d)"
trap 'PLATFORM_HOME="$ROOT"; rm -rf "$TMP_ROOT"' EXIT

PLATFORM_HOME="$TMP_ROOT/platform"
mkdir -p "$PLATFORM_HOME/app" "$PLATFORM_HOME/state/packages/installed"

PAYLOAD="$TMP_ROOT/payload"
TX_ROOT="$TMP_ROOT/tx"
BACKUP="$TX_ROOT/files"
OLD_RECORD="$TX_ROOT/old-record.json"
RECORD="$PLATFORM_HOME/state/packages/installed/demo.json"
mkdir -p "$PAYLOAD/app" "$BACKUP/app"

printf 'candidate\n' > "$PAYLOAD/app/existing.txt"
printf 'candidate-new\n' > "$PAYLOAD/app/new.txt"
printf 'original\n' > "$PLATFORM_HOME/app/existing.txt"
printf 'original\n' > "$BACKUP/app/existing.txt"
printf '{"version":"1.0.0"}\n' > "$RECORD"
cp -a "$RECORD" "$OLD_RECORD"

# Simulate candidate mutation.
printf 'changed\n' > "$PLATFORM_HOME/app/existing.txt"
printf 'created\n' > "$PLATFORM_HOME/app/new.txt"
printf '{"version":"2.0.0"}\n' > "$RECORD"

platform_tx_begin "package-test" || fail "begin"
platform_tx_register package_tx_cleanup_root "$TX_ROOT" || fail "register cleanup"
platform_tx_register package_tx_restore_record "$OLD_RECORD" "$RECORD" || fail "register record"
platform_tx_register package_tx_restore_files "$PAYLOAD" "$BACKUP" || fail "register files"
platform_tx_rollback || fail "rollback"

[[ "$(cat "$PLATFORM_HOME/app/existing.txt")" == "original" ]] || fail "existing payload not restored"
[[ ! -e "$PLATFORM_HOME/app/new.txt" ]] || fail "new payload file not removed"
grep -q '"version":"1.0.0"' "$RECORD" || fail "package record not restored"
[[ ! -e "$TX_ROOT" ]] || fail "transaction root not cleaned"
[[ "$(platform_tx_rollback_failures)" -eq 0 ]] || fail "unexpected rollback failure"

# Commit must discard rollback callbacks; candidate state remains until module cleanup.
TX_ROOT="$TMP_ROOT/commit-tx"
mkdir -p "$TX_ROOT"
printf 'candidate-commit\n' > "$PLATFORM_HOME/app/existing.txt"
platform_tx_begin "package-commit-test" || fail "commit begin"
platform_tx_register package_tx_cleanup_root "$TX_ROOT" || fail "commit register"
platform_tx_commit || fail "commit"
[[ "$(cat "$PLATFORM_HOME/app/existing.txt")" == "candidate-commit" ]] || fail "commit changed payload"
[[ -d "$TX_ROOT" ]] || fail "commit unexpectedly executed rollback cleanup"
rm -rf "$TX_ROOT"

PLATFORM_HOME="$ROOT"
echo "[OK] package transaction tests"
