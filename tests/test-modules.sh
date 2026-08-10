#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for module in "$ROOT"/modules/*; do
  [[ -d "$module" ]] || continue

  # Library-only/internal modules (for example lifecycle) are valid and do not
  # expose CLI commands. Only dispatchable modules with commands/ must provide
  # an executable help command.
  [[ -d "$module/commands" ]] || continue

  [[ -x "$module/commands/help.sh" ]] || {
    echo "[ERROR] Missing help.sh: $module"
    exit 1
  }
done

# Site update storage overlay must only detect Git-managed additions/modifications
# below storage/app/public. Runtime uploads outside Git remain untouched.
source "$ROOT/modules/site/lib/update.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo"
git -C "$repo" init -q
git -C "$repo" config user.email "platform-test@example.invalid"
git -C "$repo" config user.name "Platform Test"
mkdir -p "$repo/storage/app/public" "$repo/app"
printf 'old\n' > "$repo/storage/app/public/logo.png"
printf 'code-v1\n' > "$repo/app/example.php"
git -C "$repo" add .
git -C "$repo" commit -qm "initial"
old_commit="$(git -C "$repo" rev-parse HEAD)"
printf 'new\n' > "$repo/storage/app/public/logo.png"
printf 'code-v2\n' > "$repo/app/example.php"
printf 'runtime-only\n' > "$repo/storage/app/public/runtime-upload.png"
git -C "$repo" add storage/app/public/logo.png app/example.php
git -C "$repo" commit -qm "update"
new_commit="$(git -C "$repo" rev-parse HEAD)"

changes="$(site_update_storage_changed_files "$repo" "$old_commit" "$new_commit")"
[[ "$changes" == "storage/app/public/logo.png" ]] || {
  echo "[ERROR] Git-managed storage detection không đúng: $changes"
  exit 1
}

if grep -q 'runtime-upload.png' <<<"$changes"; then
  echo "[ERROR] Runtime upload không được đưa vào Git storage sync."
  exit 1
fi

if grep -q 'app/example.php' <<<"$changes"; then
  echo "[ERROR] Source code ngoài storage/app/public không được đưa vào storage sync."
  exit 1
fi

echo "[OK] module tests"
