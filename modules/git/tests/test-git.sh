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
grep -q -- '--require-compatible-main' "$MIGRATE"
grep -q -- '--require-identical-main' "$MIGRATE"
grep -q '^github_read_fallback()' "$MIGRATE"
grep -q '^repo_main_for_read()' "$MIGRATE"
grep -q 'git@github-\*:\*)' "$MIGRATE"
grep -q "printf 'git@github.com:%s" "$MIGRATE"
grep -q 'SSH alias kho hiện tại không truy cập được' "$MIGRATE"
grep -q 'old_repo_read=' "$MIGRATE"
grep -q 'new_repo_read=' "$MIGRATE"
grep -q 'old_main_ref=' "$MIGRATE"
grep -q 'new_main_ref=' "$MIGRATE"
grep -q 'GIT.MAIN_LINEAGE_INCOMPATIBLE' "$MIGRATE"
grep -q 'old/main must be ancestor of new/main' "$MIGRATE"
grep -q 'Main lineage : COMPATIBLE' "$MIGRATE"
grep -q 'DIRTY (PRESERVED; origin URL only)' "$MIGRATE"
grep -q 'compatible-main chỉ đổi địa chỉ origin nên các thay đổi này sẽ được giữ nguyên' "$MIGRATE"
grep -q 'require_compatible_main == 1' "$MIGRATE"
grep -q 'fetch --no-tags "$old_repo_read"' "$MIGRATE"
grep -q 'fetch --no-tags "$new_repo_read"' "$MIGRATE"
grep -q 'merge-base --is-ancestor "$old_main_ref" "$new_main_ref"' "$MIGRATE"
grep -q 'merge-base --is-ancestor "$old_main_ref" "origin/main"' "$MIGRATE"
grep -q 'merge-base --is-ancestor' "$MIGRATE"
grep -q 'remote set-url origin' "$MIGRATE"
grep -q 'rollback_remote' "$MIGRATE"
grep -q 'inventory_sync' "$MIGRATE"
grep -q 'platform_audit_try "git" "migrate-remote"' "$MIGRATE"
! grep -Eq 'reset --hard|pull |checkout -f|switch -f' "$MIGRATE"
grep -q 'migrate-remote <site>' "$HELP"
grep -q -- '--require-compatible-main' "$HELP"

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
    printf '[FAIL] git verify missing error id %s\n%s\n' "$expected_error_id" "$status" "$output" >&2
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
echo "[OK] Git Module helpers + compatible-main dirty-preservation + legacy GitHub alias fallback + Inventory sync contract"
