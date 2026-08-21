#!/usr/bin/env bash
set -Eeuo pipefail
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
ROOT="${PLATFORM_HOME:-$SCRIPT_ROOT}"
FILE="$ROOT/modules/git/lib/git.sh"
MIGRATE="$ROOT/modules/git/commands/migrate-remote.sh"
BOOTSTRAP="$ROOT/modules/git/commands/bootstrap-remote.sh"
BOOTSTRAP_LIB="$ROOT/modules/git/lib/bootstrap-remote.sh"
SYNC="$ROOT/modules/git/commands/sync-repositories.sh"
SYNC_LIB="$ROOT/modules/git/lib/sync-repositories.sh"
UPDATE="$ROOT/modules/git/commands/update.sh"
HELP="$ROOT/modules/git/commands/help.sh"

for fn in platform_git_normalize_safe_directories platform_git_trust platform_git_verify platform_git_copy_metadata; do
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
grep -q 'old_main_ref=' "$MIGRATE"
grep -q 'new_main_ref=' "$MIGRATE"
grep -q 'GIT.MAIN_LINEAGE_INCOMPATIBLE' "$MIGRATE"
grep -q 'old/main must be ancestor of new/main' "$MIGRATE"
grep -q 'Main lineage : COMPATIBLE' "$MIGRATE"
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

[[ -x "$BOOTSTRAP" ]]
[[ -f "$BOOTSTRAP_LIB" ]]
grep -q 'bootstrap-remote <site>' "$HELP"
grep -q -- '--replace-existing' "$HELP"
grep -q -- '--replace-existing' "$BOOTSTRAP_LIB"
grep -q 'target_refs=' "$BOOTSTRAP_LIB"
grep -q 'GIT.TARGET_NOT_EMPTY' "$BOOTSTRAP_LIB"
grep -q 'GIT.TARGET_MAIN_MISSING' "$BOOTSTRAP_LIB"
grep -q 'refs/platform/write-probe/bootstrap-main' "$BOOTSTRAP_LIB"
grep -q 'refs/platform/bootstrap-backup/main-' "$BOOTSTRAP_LIB"
grep -q 'GIT.TARGET_BACKUP_FAILED' "$BOOTSTRAP_LIB"
grep -q 'GIT.BOOTSTRAP_REPLACE_FAILED' "$BOOTSTRAP_LIB"
grep -q -- '--force-with-lease="refs/heads/main:$target_main_head"' "$BOOTSTRAP_LIB"
! grep -Eq -- 'push[[:space:]]+--force([[:space:]]|$)' "$BOOTSTRAP_LIB"
grep -q 'Other refs   : .*PRESERVED' "$BOOTSTRAP_LIB"
grep -q 'GIT.TARGET_NOT_WRITABLE' "$BOOTSTRAP_LIB"
grep -q 'GIT.TARGET_DELETE_DENIED' "$BOOTSTRAP_LIB"
grep -q 'refs/heads/main' "$BOOTSTRAP_LIB"
grep -q 'GIT.BOOTSTRAP_SHA_MISMATCH' "$BOOTSTRAP_LIB"
grep -q 'GIT.BOOTSTRAP_TREE_MISMATCH' "$BOOTSTRAP_LIB"
grep -q 'remote set-url origin' "$BOOTSTRAP_LIB"
grep -q '^rollback_remote()' "$BOOTSTRAP_LIB"
grep -q '^rollback_target_main()' "$BOOTSTRAP_LIB"
grep -q '^rollback_cutover()' "$BOOTSTRAP_LIB"
grep -q 'GIT.INVENTORY_SYNC_FAILED' "$BOOTSTRAP_LIB"
grep -q 'if ! inventory_sync "$site"' "$BOOTSTRAP_LIB"
grep -q 'rollback_cutover' "$BOOTSTRAP_LIB"
grep -q 'platform_audit_try "git" "bootstrap-remote"' "$BOOTSTRAP_LIB"
! grep -Eq 'reset --hard|pull |checkout -f|switch -f' "$BOOTSTRAP_LIB"

grep -q 'PLATFORM_TUNGOCVAN_GITHUB_IDENTITY_FILE' "$BOOTSTRAP_LIB"
grep -q '/root/.ssh/github_tungocvan_ed25519' "$BOOTSTRAP_LIB"
grep -q '^target_git()' "$BOOTSTRAP_LIB"
grep -q 'GIT_SSH_COMMAND="$target_ssh_command" git' "$BOOTSTRAP_LIB"
grep -q 'target_git ls-remote "$target_repo"' "$BOOTSTRAP_LIB"
grep -q 'target_git -C "$path" fetch --prune origin' "$BOOTSTRAP_LIB"
! grep -q 'github-tungocvan' "$BOOTSTRAP_LIB"

push_line="$(grep -n 'source_ref:refs/heads/main' "$BOOTSTRAP_LIB" | head -n1 | cut -d: -f1)"
sha_line="$(grep -n 'GIT.BOOTSTRAP_SHA_MISMATCH' "$BOOTSTRAP_LIB" | head -n1 | cut -d: -f1)"
remote_line="$(grep -n 'remote set-url origin' "$BOOTSTRAP_LIB" | tail -n1 | cut -d: -f1)"
sync_bootstrap_line="$(grep -n 'if ! inventory_sync "$site"' "$BOOTSTRAP_LIB" | tail -n1 | cut -d: -f1)"
[[ -n "$push_line" && -n "$sha_line" && -n "$remote_line" && -n "$sync_bootstrap_line" ]]
(( sha_line > push_line ))
(( remote_line > sha_line ))
(( sync_bootstrap_line > remote_line ))

[[ -x "$SYNC" ]]
[[ -f "$SYNC_LIB" ]]
grep -q 'sync-repositories --from=' "$HELP"
grep -q 'GIT.SYNC_TARGET_AHEAD' "$SYNC_LIB"
grep -q 'GIT.SYNC_DIVERGED' "$SYNC_LIB"
grep -q 'merge-base --is-ancestor "$target_ref" "$source_ref"' "$SYNC_LIB"
grep -q 'merge-base --is-ancestor "$source_ref" "$target_ref"' "$SYNC_LIB"
grep -q 'source_ref:refs/heads/main' "$SYNC_LIB"
grep -q 'GIT.SYNC_SHA_MISMATCH' "$SYNC_LIB"
grep -q 'GIT.SYNC_TREE_MISMATCH' "$SYNC_LIB"
grep -q 'Force push   : NO' "$SYNC_LIB"
grep -q 'Site origin  : NO CHANGE' "$SYNC_LIB"
grep -q 'Inventory    : NO CHANGE' "$SYNC_LIB"
grep -q 'Commits sync :' "$SYNC_LIB"
grep -q 'Files change :' "$SYNC_LIB"
grep -q 'COMMITS SẼ ĐỒNG BỘ' "$SYNC_LIB"
grep -q 'FILES SẼ THAY ĐỔI' "$SYNC_LIB"
grep -q 'rev-list --count' "$SYNC_LIB"
grep -q 'diff --name-status' "$SYNC_LIB"
grep -q 'tối đa 30 commit' "$SYNC_LIB"
grep -q 'tối đa 50 file' "$SYNC_LIB"
! grep -Eq -- '--force|force-with-lease|reset --hard|pull |checkout -f|switch -f|remote set-url|inventory_sync|deploy run|docker compose' "$SYNC_LIB"

grep -q 'inventory_sync "$site"' "$UPDATE"
grep -q 'Inventory synced' "$UPDATE"
merge_line="$(grep -n 'merge --ff-only' "$UPDATE" | head -n1 | cut -d: -f1)"
verify_line="$(grep -n 'platform_git_verify "$path"' "$UPDATE" | tail -n1 | cut -d: -f1)"
sync_line="$(grep -n 'inventory_sync "$site"' "$UPDATE" | tail -n1 | cut -d: -f1)"
[[ -n "$merge_line" && -n "$verify_line" && -n "$sync_line" ]]
(( sync_line > merge_line ))
(( sync_line > verify_line ))

assert_git_verify_error() {
  local expected_exit="$1" expected_error_id="$2"
  shift 2
  local output status
  set +e
  output="$(PLATFORM_HOME="$ROOT" "$ROOT/bin/platform" git verify "$@" 2>&1)"
  status=$?
  set -e
  [[ "$status" -eq "$expected_exit" ]] || { printf '[FAIL] git verify expected exit %s, got %s\n%s\n' "$expected_exit" "$status" "$output" >&2; exit 1; }
  [[ "$output" == *"[$expected_error_id]"* ]] || { printf '[FAIL] git verify missing error id %s\n%s\n' "$expected_error_id" "$status" "$output" >&2; exit 1; }
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
assert_git_verify_error 2 GIT.ARGUMENT_REQUIRED
assert_git_verify_error 3 GIT.PATH_NOT_FOUND "$TMP_DIR/missing"
mkdir -p "$TMP_DIR/not-repo"
assert_git_verify_error 3 GIT.NOT_REPOSITORY "$TMP_DIR/not-repo"

bash -n "$MIGRATE"
bash -n "$BOOTSTRAP"
bash -n "$BOOTSTRAP_LIB"
bash -n "$SYNC"
bash -n "$SYNC_LIB"
bash -n "$UPDATE"
echo "[OK] Git Module helpers + compatible-main + bootstrap replace-existing rollback + repository sync preview + Inventory sync contract"
