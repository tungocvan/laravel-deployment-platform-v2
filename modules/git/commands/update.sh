#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"

site="${1:-}"
shift || true
[[ -n "$site" ]] || die "USAGE: platform-v2 git update <site> [--dry-run] [--yes]"

dry_run=0
yes=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    --yes) yes=1 ;;
    *) die "Option không hợp lệ: $arg" ;;
  esac
done

path="$(inventory_get_field "$site" path 2>/dev/null || true)"
[[ -n "$path" ]] || die "Site không tồn tại trong Inventory: $site"
platform_git_verify "$path"

branch="$(platform_git_branch "$path")"
[[ "$branch" != "DETACHED" ]] || die "Từ chối update khi repository đang detached HEAD."
remote="$(platform_git_remote "$path")"
[[ -n "$remote" ]] || die "Repository không có remote origin: $path"

# Runtime artifacts are created/managed by Platform and must not block a safe
# source-code update. Tracked source modifications remain blocking.
status_blocking="$(
  git -C "$path" status --porcelain --untracked-files=all \
    -- . \
    ':(exclude).env' \
    ':(exclude).docker-platform.env' \
    ':(exclude)compose.queue.yaml' \
    ':(exclude)compose.socket.yaml' \
    ':(exclude)compose.scheduler.yaml'
)"

if [[ -n "$status_blocking" ]]; then
  echo "[ERROR] Working tree có thay đổi source cần xử lý trước khi update:"
  printf '%s\n' "$status_blocking"
  die "Working tree source không sạch. Commit/stash thay đổi source trước khi update."
fi

old_head="$(git -C "$path" rev-parse HEAD)"
echo "[GIT 01/03] Fetch origin"
git -C "$path" fetch --prune origin

upstream="origin/$branch"
git -C "$path" rev-parse --verify "$upstream" >/dev/null 2>&1 \
  || die "Không tìm thấy upstream: $upstream"

counts="$(git -C "$path" rev-list --left-right --count "HEAD...$upstream")"
ahead="${counts%%[[:space:]]*}"
behind="${counts##*[[:space:]]}"

cat <<EOF
=========================================================
GIT UPDATE PLAN
=========================================================
Site         : $site
Path         : $path
Remote       : $remote
Branch       : $branch
Current HEAD : $old_head
Upstream     : $upstream
Ahead        : $ahead
Behind       : $behind
Strategy     : FAST-FORWARD ONLY
Ignored      : .env, .docker-platform.env, compose.{queue,socket,scheduler}.yaml
=========================================================
EOF

if (( ahead > 0 && behind > 0 )); then
  die "Branch đã diverged với $upstream. Từ chối update tự động."
fi
if (( ahead > 0 )); then
  die "Local branch đang ahead $ahead commit. Từ chối update tự động."
fi
if (( behind == 0 )); then
  echo "[OK] Code đã là phiên bản mới nhất."
  exit 0
fi

if (( dry_run == 1 )); then
  echo "[DRY-RUN] Sẽ fast-forward $behind commit; không thay đổi working tree."
  exit 0
fi
[[ "$yes" -eq 1 ]] || die "Thiếu --yes. Hãy chạy --dry-run trước hoặc xác nhận qua menu."

echo "[GIT 02/03] Fast-forward $upstream"
git -C "$path" merge --ff-only "$upstream"
new_head="$(git -C "$path" rev-parse HEAD)"

echo "[GIT 03/03] Verify + sync Inventory"
platform_git_verify "$path"
inventory_sync "$site" >/dev/null
printf '[OK] Code updated: %s -> %s\n' "$old_head" "$new_head"
printf '[OK] Inventory synced: %s @ %s\n' "$site" "$new_head"
