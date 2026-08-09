#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLATFORM_HOME="$ROOT"
source "$ROOT/core/bootstrap.sh"
source "$ROOT/core/lib/package.sh"
source "$ROOT/modules/package/lib/package.sh"
source "$ROOT/modules/package/lib/upgrade-audit.sh"

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

# Audit outcomes are deterministic and contain only fixed-schema evidence.
export PLATFORM_AUDIT_ROOT="$TMP_ROOT/audit"
export PLATFORM_AUDIT_NOW="2026-08-09T03:30:00Z"
export PLATFORM_AUDIT_ACTOR="package-test"

PLATFORM_TX_FAILED_ROLLBACKS=0
package_upgrade_audit_failure demo PACKAGE.INSTALL_FAILED package-upgrade:demo
PLATFORM_TX_FAILED_ROLLBACKS=2
package_upgrade_audit_failure demo PACKAGE.VERIFY_FAILED package-upgrade:demo
package_upgrade_audit_success demo package-upgrade:demo

AUDIT_FILE="$PLATFORM_AUDIT_ROOT/events-2026-08.jsonl"
[[ -f "$AUDIT_FILE" ]] || fail "package audit file missing"
[[ "$(wc -l < "$AUDIT_FILE")" -eq 3 ]] || fail "package audit event count"

python3 - "$AUDIT_FILE" <<'PY' || exit 1
import json,sys
with open(sys.argv[1], encoding='utf-8') as f:
    rows=[json.loads(line) for line in f]
assert rows[0]['module']=='package'
assert rows[0]['command']=='upgrade'
assert rows[0]['target']=='demo'
assert rows[0]['result']=='failed'
assert rows[0]['error_code']=='PACKAGE.INSTALL_FAILED'
assert rows[0]['transaction_id']=='package-upgrade:demo'
assert rows[0]['rollback_status']=='success'
assert rows[1]['result']=='rollback-partial'
assert rows[1]['error_code']=='PACKAGE.VERIFY_FAILED'
assert rows[1]['rollback_status']=='partial'
assert rows[2]['result']=='success'
assert rows[2]['error_code'] is None
assert rows[2]['rollback_status']=='not-required'
PY

# Audit is best-effort and must not change the package workflow result.
PLATFORM_AUDIT_ROOT="/proc/platform-audit-denied" package_upgrade_audit_success demo package-upgrade:demo

PLATFORM_HOME="$ROOT"
echo "[OK] package transaction tests"
