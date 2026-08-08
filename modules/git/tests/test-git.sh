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

echo "[OK] Git Module dev.2 helpers"
