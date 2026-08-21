#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
source "$PLATFORM_HOME/modules/inventory/lib/inventory.sh"
source "$PLATFORM_HOME/modules/git/lib/git.sh"

site="${1:-}"
shift || true
[[ -n "$site" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.ARGUMENT_REQUIRED" "USAGE: platform-v2 git bootstrap-remote <site> --to=<empty-git-url> [--dry-run] [--yes]"

target_repo=""
dry_run=0
yes=0
for arg in "$@"; do
  case "$arg" in
    --to=*) target_repo="${arg#*=}" ;;
    --dry-run) dry_run=1 ;;
    --yes) yes=1 ;;
    *) platform_die "$PLATFORM_EXIT_USAGE" "GIT.INVALID_OPTION" "Option không hợp lệ trong bootstrap mode: $arg" ;;
  esac
done
[[ -n "$target_repo" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.TARGET_REMOTE_REQUIRED" "Repository mới không được rỗng."

path="$(inventory_get_field "$site" path 2>/dev/null || true)"
[[ -n "$path" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.SITE_NOT_FOUND" "Site không tồn tại trong Inventory: $site"
platform_git_verify "$path"
branch="$(platform_git_branch "$path")"
[[ "$branch" == "main" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.MAIN_BRANCH_REQUIRED" "Bootstrap repository mới chỉ áp dụng khi site đang ở branch main; hiện tại: $branch"
current_repo="$(platform_git_remote "$path")"
[[ -n "$current_repo" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.ORIGIN_MISSING" "Repository không có remote origin: $path"
[[ "$current_repo" != "$target_repo" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.TARGET_EQUALS_CURRENT" "Repository mới đang trùng repository hiện tại."
site_head="$(git -C "$path" rev-parse HEAD)"

# Repository URLs remain canonical. Transport identity is selected separately so
# Inventory/origin never need to persist an SSH host alias.
target_ssh_command=""
target_identity_file="${PLATFORM_TUNGOCVAN_GITHUB_IDENTITY_FILE:-/root/.ssh/github_tungocvan_ed25519}"
if [[ "$target_repo" =~ ^git@github\.com:tungocvan/.+\.git$ ]] && [[ -r "$target_identity_file" ]]; then
  target_ssh_command="ssh -i $target_identity_file -o IdentitiesOnly=yes"
fi

target_git() {
  if [[ -n "$target_ssh_command" ]]; then
    GIT_SSH_COMMAND="$target_ssh_command" git "$@"
  else
    git "$@"
  fi
}

source_verify_repo="$current_repo"
if [[ "$current_repo" =~ ^git@([^:]+):([^/]+)/(.+\.git)$ ]]; then
  source_host="${BASH_REMATCH[1]}"
  source_path="${BASH_REMATCH[2]}/${BASH_REMATCH[3]}"
  if [[ "$source_host" != "github.com" ]] && ! ssh -G "$source_host" 2>/dev/null | grep -q '^hostname github\.com$'; then
    source_verify_repo="git@github.com:$source_path"
    echo "[WARN] SSH alias kho hiện tại không khả dụng; dùng GitHub canonical transport chỉ để đọc source:"
    echo "       $current_repo"
    echo "    -> $source_verify_repo"
  fi
fi

source_main_head="$(git ls-remote --heads "$source_verify_repo" refs/heads/main | awk 'NR==1 {print $1}')"
[[ -n "$source_main_head" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.CURRENT_MAIN_NOT_FOUND" "Không đọc được branch main của kho hiện tại: $current_repo"

set +e
target_refs="$(target_git ls-remote "$target_repo" 2>/dev/null)"
target_read_exit=$?
set -e
[[ "$target_read_exit" -eq 0 ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.TARGET_UNREACHABLE" "Không truy cập được kho mới: $target_repo"
if [[ -n "$target_refs" ]]; then
  cat <<EOF
=========================================================
EMPTY REPOSITORY CHECK — FAILED
=========================================================
New repo     : $target_repo
State        : NOT EMPTY
=========================================================
EOF
  platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.TARGET_NOT_EMPTY" "Kho mới phải hoàn toàn trống trước khi bootstrap."
fi

source_ref="refs/platform/repository-bootstrap/source-main"
git -C "$path" fetch --no-tags "$source_verify_repo" "refs/heads/main:$source_ref" >/dev/null
trap 'git -C "$path" update-ref -d "$source_ref" >/dev/null 2>&1 || true; git -C "$path" update-ref -d "refs/platform/repository-bootstrap/new-main" >/dev/null 2>&1 || true' EXIT
source_tree="$(git -C "$path" rev-parse "$source_ref^{tree}")"

git -C "$path" merge-base --is-ancestor "$site_head" "$source_ref" >/dev/null 2>&1 || \
  platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.SITE_HEAD_NOT_IN_SOURCE_MAIN" "HEAD hiện tại của site không thuộc history kho cũ/main. Từ chối đổi origin sau bootstrap."

status_blocking="$(git -C "$path" status --porcelain --untracked-files=all -- . ':(exclude).env' ':(exclude).docker-platform.env' ':(exclude)compose.queue.yaml' ':(exclude)compose.socket.yaml' ':(exclude)compose.scheduler.yaml')"

cat <<EOF
=========================================================
BOOTSTRAP EMPTY REPOSITORY PLAN
=========================================================
Site         : $site
Path         : $path
Site HEAD    : $site_head
Source repo  : $current_repo
Source main  : $source_main_head
Source tree  : $source_tree
New repo     : $target_repo
New state    : EMPTY
Copy         : old/main -> new/main
Site code    : PRESERVE
Deploy       : NO
Database     : NO
Origin       : CHANGE ONLY AFTER PUSH + VERIFY
Inventory    : SYNC AFTER SUCCESS
EOF
if [[ -n "$target_ssh_command" ]]; then
  echo "Target auth  : dedicated tungocvan SSH identity (transport only)"
else
  echo "Target auth  : default Git SSH transport"
fi
if [[ -n "$status_blocking" ]]; then
  echo "Worktree     : DIRTY (PRESERVED; repository source is authoritative)"
  printf '%s\n' "$status_blocking"
else
  echo "Worktree     : CLEAN"
fi
echo "========================================================="

if (( dry_run == 1 )); then
  echo "[DRY-RUN] Kho mới đang trống và source main hợp lệ. Quyền push/delete sẽ được xác minh khi chạy với --yes; site chưa bị thay đổi."
  exit 0
fi
[[ "$yes" -eq 1 ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.CONFIRMATION_REQUIRED" "Thiếu --yes. Hãy chạy --dry-run trước hoặc xác nhận qua menu."

probe_ref="refs/platform/write-probe/bootstrap-main"
if ! target_git -C "$path" push "$target_repo" "$source_ref:$probe_ref" >/dev/null; then
  platform_audit_try "git" "bootstrap-remote" "$site" "failed" "GIT.TARGET_NOT_WRITABLE" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.TARGET_NOT_WRITABLE" "Không thể ghi vào kho mới. Origin site chưa thay đổi."
fi
if ! target_git -C "$path" push "$target_repo" ":$probe_ref" >/dev/null; then
  platform_audit_try "git" "bootstrap-remote" "$site" "failed" "GIT.TARGET_DELETE_DENIED" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.TARGET_DELETE_DENIED" "Không thể xóa ref kiểm tra ở kho mới. Origin site chưa thay đổi; hãy xóa refs/platform/write-probe/bootstrap-main rồi thử lại."
fi
if ! target_git -C "$path" push "$target_repo" "$source_ref:refs/heads/main" >/dev/null; then
  platform_audit_try "git" "bootstrap-remote" "$site" "failed" "GIT.BOOTSTRAP_PUSH_FAILED" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.BOOTSTRAP_PUSH_FAILED" "Push old/main sang new/main thất bại. Origin site chưa thay đổi."
fi

new_main_head="$(target_git ls-remote --heads "$target_repo" refs/heads/main | awk 'NR==1 {print $1}')"
[[ "$new_main_head" == "$source_main_head" ]] || platform_die "$PLATFORM_EXIT_OPERATION" "GIT.BOOTSTRAP_SHA_MISMATCH" "Verify SHA new/main thất bại. Origin site chưa thay đổi."
verify_ref="refs/platform/repository-bootstrap/new-main"
target_git -C "$path" fetch --no-tags "$target_repo" "refs/heads/main:$verify_ref" >/dev/null
new_tree="$(git -C "$path" rev-parse "$verify_ref^{tree}")"
[[ "$new_tree" == "$source_tree" ]] || platform_die "$PLATFORM_EXIT_OPERATION" "GIT.BOOTSTRAP_TREE_MISMATCH" "Verify source tree new/main thất bại. Origin site chưa thay đổi."

old_repo="$current_repo"
rollback_remote() { git -C "$path" remote set-url origin "$old_repo" >/dev/null 2>&1 || true; }
git -C "$path" remote set-url origin "$target_repo"
if ! target_git -C "$path" fetch --prune origin >/dev/null; then
  rollback_remote
  platform_audit_try "git" "bootstrap-remote" "$site" "failed" "GIT.POST_BOOTSTRAP_FETCH_FAILED" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.POST_BOOTSTRAP_FETCH_FAILED" "Fetch kho mới sau cutover thất bại; origin đã rollback về kho cũ."
fi
origin_main="$(git -C "$path" rev-parse origin/main 2>/dev/null || true)"
if [[ "$origin_main" != "$source_main_head" ]]; then
  rollback_remote
  platform_audit_try "git" "bootstrap-remote" "$site" "failed" "GIT.POST_BOOTSTRAP_VERIFY_FAILED" "" "not-attempted"
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.POST_BOOTSTRAP_VERIFY_FAILED" "Verify origin/main sau cutover thất bại; origin đã rollback về kho cũ."
fi

inventory_sync "$site" >/dev/null
platform_audit_try "git" "bootstrap-remote" "$site" "success" "" "" "not-required"
git -C "$path" update-ref -d "$source_ref" >/dev/null 2>&1 || true
git -C "$path" update-ref -d "$verify_ref" >/dev/null 2>&1 || true
trap - EXIT
printf '[OK] Bootstrap repository thành công: %s main -> %s main\n' "$old_repo" "$target_repo"
printf '[OK] Verified SHA: %s\n' "$source_main_head"
printf '[OK] Verified tree: %s\n' "$source_tree"
printf '[OK] Origin site đã đổi sau verify; HEAD/worktree/deploy/database không bị thay đổi.\n'
printf '[OK] Inventory đã sync: %s\n' "$site"
