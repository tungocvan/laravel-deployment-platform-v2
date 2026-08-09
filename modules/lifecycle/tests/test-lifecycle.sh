#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$SCRIPT_DIR/../../.." && pwd)"
export PLATFORM_HOME="$ROOT"

F="$ROOT/modules/lifecycle/lib/lifecycle.sh"
TX_F="$ROOT/modules/lifecycle/lib/disable-transaction.sh"
DISABLE_CMD="$ROOT/modules/site/commands/disable.sh"

for fn in \
  site_disable site_enable site_maintenance \
  site_archive site_restore_archive site_archives \
  site_lifecycle_show
do
  grep -q "^${fn}()" "$F"
done

grep -q 'backup_verify "$site"' "$F"
grep -q 'down --remove-orphans' "$F"

if grep -q 'down -v' "$F"; then
  echo "[ERROR] Lifecycle archive không được purge volumes."
  exit 1
fi

bash -n "$F"
bash -n "$TX_F"
bash -n "$DISABLE_CMD"

grep -q 'disable-transaction.sh' "$DISABLE_CMD"
grep -q '^site_disable()' "$TX_F"
grep -q 'platform_tx_begin "$tx_id"' "$TX_F"
grep -q 'platform_tx_register site_disable_tx_enable_nginx' "$TX_F"
grep -q 'platform_tx_register site_disable_tx_start_docker' "$TX_F"
grep -q 'site_disable_tx_audit' "$TX_F"
grep -q 'platform_tx_commit' "$TX_F"

source "$ROOT/core/bootstrap.sh"
# shellcheck disable=SC1090
source "$TX_F"

TMP="$(mktemp -d)"
TRACE="$TMP/trace"
trap 'rm -rf "$TMP"' EXIT

platform_nginx_enable() {
  printf 'nginx:%s\n' "$1" >> "$TRACE"
}

deploy_compose() {
  local path="$1" action="${2:-}"
  if [[ "$action" == "up" && "${3:-}" == "-d" ]]; then
    printf 'docker:%s\n' "$path" >> "$TRACE"
    return 0
  fi
  return 1
}

platform_tx_begin "lifecycle-disable-test"
platform_tx_register site_disable_tx_enable_nginx "example.test"
platform_tx_register site_disable_tx_start_docker "/tmp/site path"
platform_tx_rollback

EXPECTED=$'docker:/tmp/site path\nnginx:example.test'
[[ "$(cat "$TRACE")" == "$EXPECTED" ]] || {
  echo "[ERROR] Lifecycle disable rollback order mismatch." >&2
  cat "$TRACE" >&2
  exit 1
}

[[ "$(platform_tx_rollback_failures)" -eq 0 ]]

export PLATFORM_AUDIT_ROOT="$TMP/audit"
export PLATFORM_AUDIT_NOW="2026-08-09T03:30:00Z"
export PLATFORM_AUDIT_ACTOR="lifecycle-test"
site_disable_tx_audit nvh success "" "site-disable:nvh" not-required
site_disable_tx_audit nvh failed SITE.DISABLE_STATE_FAILED "site-disable:nvh" success

AUDIT_FILE="$PLATFORM_AUDIT_ROOT/events-2026-08.jsonl"
python3 - "$AUDIT_FILE" <<'PY'
import json,sys
with open(sys.argv[1], encoding='utf-8') as f:
    rows=[json.loads(line) for line in f]
assert len(rows)==2
assert rows[0]['module']=='site'
assert rows[0]['command']=='disable'
assert rows[0]['target']=='nvh'
assert rows[0]['result']=='success'
assert rows[0]['transaction_id']=='site-disable:nvh'
assert rows[1]['result']=='failed'
assert rows[1]['error_code']=='SITE.DISABLE_STATE_FAILED'
assert rows[1]['rollback_status']=='success'
PY

# Audit evidence must never change the workflow result when logging itself fails.
export PLATFORM_AUDIT_NOW="invalid-date"
site_disable_tx_audit nvh success "" "site-disable:nvh" not-required

echo "[OK] Site Lifecycle transaction tests"
