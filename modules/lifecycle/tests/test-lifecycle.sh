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
grep -q 'platform_tx_begin "site-disable:' "$TX_F"
grep -q 'platform_tx_register site_disable_tx_enable_nginx' "$TX_F"
grep -q 'platform_tx_register site_disable_tx_start_docker' "$TX_F"
grep -q 'platform_tx_commit' "$TX_F"

source "$ROOT/core/bootstrap.sh"
source "$TX_F"

TRACE="$(mktemp)"
trap 'rm -f "$TRACE"' EXIT

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

echo "[OK] Site Lifecycle transaction tests"
