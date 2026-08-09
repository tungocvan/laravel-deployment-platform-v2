#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
FILE="$ROOT/modules/git/lib/git.sh"

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

echo "[OK] Git Module dev.2 helpers"
