#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"
source "$PLATFORM_HOME/modules/site/lib/repository.sh"

site="${1:-}"
shift || true
[[ -n "$site" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.ARGUMENT_REQUIRED" "USAGE: platform-v2 git migrate-remote <site> [--to=<repo>] [--require-compatible-main] [--require-identical-main] [--dry-run] [--yes]"

target_repo="$(site_default_repo)"
dry_run=0
yes=0
require_compatible_main=0
for arg in "$@"; do
  case "$arg" in
    --to=*) target_repo="${arg#*=}" ;;
    --require-compatible-main|--require-identical-main) require_compatible_main=1 ;;
    --dry-run) dry_run=1 ;;
    --yes) yes=1 ;;
    *) platform_die "$PLATFORM_EXIT_USAGE" "GIT.INVALID_OPTION" "Option không hợp lệ: $arg" ;;
  esac
done
[[ -n "$target_repo" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.TARGET_REMOTE_REQUIRED" "Target repository không được rỗng."

path="$(inventory_get_field "$site" path 2>/dev/null || true)"
[[ -n "$path" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.SITE_NOT_FOUND" "Site không tồn tại trong Inventory: $site"
platform_git_verify "$path"

branch="$(platform_git_branch "$path")"
[[ "$branch" != "DETACHED" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.DETACHED_HEAD" "Từ chối migrate remote khi repository đang detached HEAD."
current_repo="$(platform_git_remote "$path")"
[[ -n "$current_repo" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.ORIGIN_MISSING" "Repository không có remote origin: $path"
old_head="$(git -C "$path" rev-parse HEAD)"

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
  if (( require_compatible_main == 1 )); then
    echo "[WARN] Working tree có thay đổi source; compatible-main chỉ đổi địa chỉ origin nên các thay đổi này sẽ được giữ nguyên:"
    printf '%s\n' "$status_blocking"
  else
    echo "[ERROR] Working tree có thay đổi source cần xử lý trước khi migrate remote:"
    printf '%s\n' "$status_blocking"
    platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.WORKTREE_DIRTY" "Working tree source không sạch. Commit/stash thay đổi source trước khi migrate remote."
  fi
fi

if [[ "$current_repo" == "$target_repo" ]]; then
  echo "[OK] Remote origin đã đúng target: $target_repo"
  inventory_sync "$site" >/dev/null
  exit 0
fi

old_main_ref=""
new_main_ref=""
old_main_head=""
new_main_head=""
if (( require_compatible_main == 1 )); then
  [[ "$branch" == "main" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.STRICT_MAIN_BRANCH_REQUIRED" \
    "Update kho mới chỉ áp dụng khi working tree đang ở branch main; hiện tại: $branch"

  old_main_head="$(git ls-remote --heads "$current_repo" refs/heads/main | awk 'NR==1 {print $1}')"
  [[ -n "$old_main_head" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.CURRENT_MAIN_NOT_FOUND" \
    "Không đọc được branch main của kho hiện tại: $current_repo"

  new_main_head="$(git ls-remote --heads "$target_repo" refs/heads/main | awk 'NR==1 {print $1}')"
  [[ -n "$new_main_head" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.TARGET_MAIN_NOT_FOUND" \
    "Không đọc được branch main của kho mới: $target_repo"

  old_main_ref="refs/platform/repository-check/old-main"
  new_main_ref="refs/platform/repository-check/new-main"
  git -C "$path" fetch --no-tags "$current_repo" "refs/heads/main:$old_main_ref" >/dev/null
  git -C "$path" fetch --no-tags "$target_repo" "refs/heads/main:$new_main_ref" >/dev/null
  trap 'git -C "$path" update-ref -d "$old_main_ref" >/dev/null 2>&1 || true; git -C "$path" update-ref -d "$new_main_ref" >/dev/null 2>&1 || true; git -C "$path" update-ref -d "refs/platform/migrate-remote/$branch" >/dev/null 2>&1 || true' EXIT

  if ! git -C "$path" merge-base --is-ancestor "$old_main_ref" "$new_main_ref" >/dev/null 2>&1; then
    cat <<EOF
=========================================================
REPOSITORY MAIN LINEAGE CHECK — FAILED
=========================================================
Current repo : $current_repo
Current main : $old_main_head
New repo     : $target_repo
New main     : $new_main_head
Compatible   : NO
Rule         : old/main must be ancestor of new/main
=========================================================
EOF
    platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.MAIN_LINEAGE_INCOMPATIBLE" \
      "Kho mới/main không chứa đầy đủ history của kho cũ/main. Từ chối thay đổi địa chỉ repository."
  fi
fi

target_branch_head="$(git ls-remote --heads "$target_repo" "refs/heads/$branch" | awk 'NR==1 {print $1}')"
[[ -n "$target_branch_head" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.TARGET_BRANCH_NOT_FOUND" "Target repository không có branch $branch hoặc không thể truy cập: $target_repo"

temp_ref="refs/platform/migrate-remote/$branch"
git -C "$path" fetch --no-tags "$target_repo" "refs/heads/$branch:$temp_ref" >/dev/null
if (( require_compatible_main == 0 )); then
  trap 'git -C "$path" update-ref -d "$temp_ref" >/dev/null 2>&1 || true' EXIT
fi

git -C "$path" merge-base --is-ancestor "$old_head" "$temp_ref" >/dev/null 2>&1 \
  || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.TARGET_HISTORY_MISMATCH" "Current HEAD không thuộc history của target branch $branch. Từ chối đổi remote."

counts="$(git -C "$path" rev-list --left-right --count "HEAD...$temp_ref")"
ahead="${counts%%[[:space:]]*}"
behind="${counts##*[[:space:]]}"

cat <<EOF
=========================================================
GIT REMOTE MIGRATION PLAN
=========================================================
Site         : $site
Path         : $path
Branch       : $branch
Current HEAD : $old_head
Current repo : $current_repo
Target repo  : $target_repo
Target HEAD  : $target_branch_head
Ahead        : $ahead
Behind       : $behind
EOF
if (( require_compatible_main == 1 )); then
  main_relation="SAME"
  [[ "$old_main_head" != "$new_main_head" ]] && main_relation="NEW REPO AHEAD"
  cat <<EOF
Old main     : $old_main_head
New main     : $new_main_head
Main lineage : COMPATIBLE ($main_relation)
Rule         : old/main is ancestor of new/main
Mode         : REPOSITORY ADDRESS CHANGE ONLY
EOF
  if [[ -n "$status_blocking" ]]; then
    echo "Worktree     : DIRTY (PRESERVED; origin URL only)"
  else
    echo "Worktree     : CLEAN"
  fi
fi
cat <<EOF
Action       : CHANGE ORIGIN ONLY
Code update  : NO
Deploy       : NO
Inventory    : SYNC AFTER SUCCESS
=========================================================
EOF

if (( ahead > 0 )); then
  platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.LOCAL_AHEAD_TARGET" "Current branch đang ahead target $ahead commit. Từ chối đổi remote tự động."
fi
if (( dry_run == 1 )); then
  echo "[DRY-RUN] Preconditions hợp lệ; origin sẽ được đổi sang target khi chạy với --yes."
  exit 0
fi
[[ "$yes" -eq 1 ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.CONFIRMATION_REQUIRED" "Thiếu --yes. Hãy chạy --dry-run trước hoặc xác nhận qua menu."

old_repo="$current_repo"
rollback_remote() {
  git -C "$path" remote set-url origin "$old_repo" >/dev/null 2>&1 || true
}

git -C "$path" remote set-url origin "$target_repo"
if ! git -C "$path" fetch --prune origin; then
  rollback_remote
  platform_audit_try "git" "migrate-remote" "$site" "failed" "GIT.TARGET_FETCH_FAILED" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.TARGET_FETCH_FAILED" "Fetch target thất bại; origin đã rollback về repository cũ."
fi

origin_head="$(git -C "$path" rev-parse "origin/$branch" 2>/dev/null || true)"
if [[ -z "$origin_head" ]] || ! git -C "$path" merge-base --is-ancestor "$old_head" "origin/$branch" >/dev/null 2>&1; then
  rollback_remote
  platform_audit_try "git" "migrate-remote" "$site" "failed" "GIT.POST_MIGRATION_VERIFY_FAILED" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.POST_MIGRATION_VERIFY_FAILED" "Verify target sau đổi remote thất bại; origin đã rollback về repository cũ."
fi

if (( require_compatible_main == 1 )); then
  if ! git -C "$path" merge-base --is-ancestor "$old_main_ref" "origin/main" >/dev/null 2>&1; then
    rollback_remote
    platform_audit_try "git" "migrate-remote" "$site" "failed" "GIT.POST_MAIN_LINEAGE_FAILED" "" "not-attempted"
    platform_die "$PLATFORM_EXIT_OPERATION" "GIT.POST_MAIN_LINEAGE_FAILED" \
      "Main của origin sau thay đổi không còn chứa history kho cũ; origin đã rollback."
  fi
fi

inventory_sync "$site" >/dev/null
platform_audit_try "git" "migrate-remote" "$site" "success" "" "" "not-required"

git -C "$path" update-ref -d "$temp_ref" >/dev/null 2>&1 || true
[[ -n "$old_main_ref" ]] && git -C "$path" update-ref -d "$old_main_ref" >/dev/null 2>&1 || true
[[ -n "$new_main_ref" ]] && git -C "$path" update-ref -d "$new_main_ref" >/dev/null 2>&1 || true
trap - EXIT
printf '[OK] Remote migrated: %s -> %s\n' "$old_repo" "$target_repo"
printf '[OK] HEAD giữ nguyên: %s\n' "$old_head"
printf '[OK] Inventory đã sync; code/deploy không bị thay đổi.\n'
