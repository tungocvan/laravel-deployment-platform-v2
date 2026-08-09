#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_HOME="$ROOT"
source "$ROOT/core/lib/audit.sh"

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export PLATFORM_AUDIT_ROOT="$TMP/audit"
export PLATFORM_AUDIT_NOW="2026-08-09T02:50:00Z"
export PLATFORM_AUDIT_ACTOR="phase3-test"

platform_audit_write package upgrade Package-003 success "" tx-123 not-required || fail "write success event"
platform_audit_write site disable nvh failed SITE.DISABLE_FAILED tx-456 success || fail "write failed event"

FILE="$PLATFORM_AUDIT_ROOT/events-2026-08.jsonl"
[[ -f "$FILE" ]] || fail "audit file missing"
[[ "$(wc -l < "$FILE")" -eq 2 ]] || fail "audit must append two lines"
[[ "$(stat -c '%a' "$PLATFORM_AUDIT_ROOT")" == "700" ]] || fail "audit root permissions"
[[ "$(stat -c '%a' "$FILE")" == "600" ]] || fail "audit file permissions"

python3 - "$FILE" <<'PY' || exit 1
import json,sys
with open(sys.argv[1], encoding='utf-8') as f:
    rows=[json.loads(line) for line in f]
assert rows[0] == {
    'schema_version':1,
    'at':'2026-08-09T02:50:00Z',
    'actor':'phase3-test',
    'module':'package',
    'command':'upgrade',
    'target':'Package-003',
    'result':'success',
    'error_code':None,
    'transaction_id':'tx-123',
    'rollback_status':'not-required',
}
assert rows[1]['result']=='failed'
assert rows[1]['error_code']=='SITE.DISABLE_FAILED'
assert rows[1]['rollback_status']=='success'
for row in rows:
    assert set(row) == {'schema_version','at','actor','module','command','target','result','error_code','transaction_id','rollback_status'}
    lowered=' '.join(str(v).lower() for v in row.values())
    for forbidden in ('password=', 'token=', 'private key', 'app_key='):
        assert forbidden not in lowered
PY

if platform_audit_write package upgrade demo invalid-result; then
  fail "invalid result accepted"
fi
if platform_audit_write package upgrade demo success "" "" invalid-rollback; then
  fail "invalid rollback status accepted"
fi
if platform_audit_write "" upgrade demo success; then
  fail "empty module accepted"
fi

export PLATFORM_AUDIT_NOW="not-a-date"
if platform_audit_write package upgrade demo success; then
  fail "invalid date accepted"
fi

echo "[OK] audit tests"
