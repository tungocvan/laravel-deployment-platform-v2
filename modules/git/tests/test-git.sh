#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"
FILE="$ROOT/modules/git/lib/git.sh"
MIGRATE="$ROOT/modules/git/commands/migrate-remote.sh"
UPDATE="$ROOT/modules/git/commands/update.sh"
HELP="$ROOT/modules/git/commands/help.sh"

for fn in \
  platform_git_normalize_safe_directories \
  platform_git_trust \
  platform_git_verify \
  platform_git_copy_metadata
do
  grep -q "^${fn}()" "$FILE"
done

grep -q 'unset-all safe.directory' "$FILE"
grep -q "grep -qx ''" "$FILE"

[[ -x "$MIGRATE" ]]
grep -q 'site_default_repo' "$MIGRATE"
grep -q -- '--dry-run' "$MIGRATE"
grep -q -- '--yes' "$MIGRATE"
grep -q -- '--require-identical-main' "$MIGRATE"
grep -q 'old_main_head=' "$MIGRATE"
grep -q 'new_main_head=' "$MIGRATE"
grep -q 'GIT.MAIN_NOT_IDENTICAL' "$MIGRATE"
grep -q 'Main equal   : YES (100% same commit)' "$MIGRATE"
grep -q 'git -C "$path" ls-remote --heads origin refs/heads/main' "$MIGRATE"
grep -q 'merge-base --is-ancestor' "$MIGRATE"
grep -q 'remote set-url origin' "$MIGRATE"
grep -q 'rollback_remote' "$MIGRATE"
grep -q 'inventory_sync' "$MIGRATE"
grep -q 'platform_audit_try "git" "migrate-remote"' "$MIGRATE"
! grep -Eq 'reset --hard|pull |checkout -f|switch -f' "$MIGRATE"
grep -q 'migrate-remote <site>' "$HELP"
grep -q -- '--require-identical-main' "$HELP"

# A successful fast-forward must immediately reconcile Inventory Git metadata.
grep -q 'inventory_sync "$site"' "$UPDATE"
grep -q 'Inventory synced' "$UPDATE"
merge_line="$(grep -n 'merge --ff-only' "$UPDATE" | head -n1 | cut -d: -f1)"
verify_line="$(grep -n 'platform_git_verify "$path"' "$UPDATE" | tail -n1 | cut -d: -f1)"
sync_line="$(grep -n 'inventory_sync "$site"' "$UPDATE" | tail -n1 | cut -d: -f1)"
[[ -n "$merge_line" && -n "$verify_line" && -n "$sync_line" ]]
(( sync_line > merge_line ))
(( sync_line > verify_line ))

assert_git_verify_error() {
  local expected_exit="$1"
  local expected_error_id="$2"
  shift 2

  local output status
  set +e
  output="$(PLATFORM_HOME="$ROOT" "$ROOT/bin/platform" git verify "$@" 2>&1)"
  status=$?
  set -e

  [[ "$status" -eq "$expected_exit" ]] || {
    printf '[FAIL] git verify expected exit %s, got %s\n%s\n' "$expected_exit" "$status" "$output" >&2
    exit 1
  }
  [[ "$output" == *"[$expected_error_id]"* ]] || {
    printf '[FAIL] git verify missing error id %s\n%s\n' "$expected_error_id" "$output" >&2
    exit 1
  }
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

assert_git_verify_error 2 GIT.ARGUMENT_REQUIRED
assert_git_verify_error 3 GIT.PATH_NOT_FOUND "$TMP_DIR/missing"
mkdir -p "$TMP_DIR/not-repo"
assert_git_verify_error 3 GIT.NOT_REPOSITORY "$TMP_DIR/not-repo"

bash -n "$MIGRATE"
bash -n "$UPDATE"
echo "[OK] Git Module helpers + strict identical-main remote update + Inventory sync contract"
