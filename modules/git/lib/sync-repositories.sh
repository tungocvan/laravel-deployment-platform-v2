#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

source_repo=""
target_repo=""
dry_run=0
yes=0

for arg in "$@"; do
  case "$arg" in
    --from=*) source_repo="${arg#*=}" ;;
    --to=*) target_repo="${arg#*=}" ;;
    --dry-run) dry_run=1 ;;
    --yes) yes=1 ;;
    *) platform_die "$PLATFORM_EXIT_USAGE" "GIT.INVALID_OPTION" "Option không hợp lệ: $arg" ;;
  esac
done

[[ -n "$source_repo" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.SOURCE_REMOTE_REQUIRED" "Thiếu --from=<source-repo>."
[[ -n "$target_repo" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.TARGET_REMOTE_REQUIRED" "Thiếu --to=<target-repo>."
[[ "$source_repo" != "$target_repo" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.SYNC_SAME_REPOSITORY" "Kho nguồn và kho đích đang trùng nhau."

identity_file="${PLATFORM_TUNGOCVAN_GITHUB_IDENTITY_FILE:-/root/.ssh/github_tungocvan_ed25519}"

canonical_verify_repo() {
  local repo="$1" host path
  if [[ "$repo" =~ ^git@([^:]+):(.+\.git)$ ]]; then
    host="${BASH_REMATCH[1]}"
    path="${BASH_REMATCH[2]}"
    if [[ "$host" == github-* ]] && [[ "$host" != "github.com" ]] && ! ssh -G "$host" 2>/dev/null | grep -q '^hostname github\.com$'; then
      printf 'git@github.com:%s' "$path"
      return 0
    fi
  fi
  printf '%s' "$repo"
}

repo_git() {
  local repo="$1"
  shift
  if [[ "$repo" =~ ^git@github\.com:tungocvan/.+\.git$ ]] && [[ -r "$identity_file" ]]; then
    GIT_SSH_COMMAND="ssh -i $identity_file -o IdentitiesOnly=yes" git "$@"
  else
    git "$@"
  fi
}

source_effective="$(canonical_verify_repo "$source_repo")"
target_effective="$(canonical_verify_repo "$target_repo")"

if [[ "$source_effective" != "$source_repo" ]]; then
  echo "[WARN] SSH alias kho nguồn không khả dụng; dùng GitHub canonical transport chỉ để sync:"
  echo "       $source_repo"
  echo "    -> $source_effective"
fi
if [[ "$target_effective" != "$target_repo" ]]; then
  echo "[WARN] SSH alias kho đích không khả dụng; dùng GitHub canonical transport chỉ để sync:"
  echo "       $target_repo"
  echo "    -> $target_effective"
fi

source_main="$(repo_git "$source_effective" ls-remote --heads "$source_effective" refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
[[ -n "$source_main" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.SYNC_SOURCE_MAIN_NOT_FOUND" "Không đọc được source/main: $source_repo"

set +e
target_refs="$(repo_git "$target_effective" ls-remote "$target_effective" 2>/dev/null)"
target_exit=$?
set -e
[[ "$target_exit" -eq 0 ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.SYNC_TARGET_UNREACHABLE" "Không truy cập được kho đích: $target_repo"

target_main="$(printf '%s\n' "$target_refs" | awk '$2=="refs/heads/main" {print $1; exit}')"
if [[ -n "$target_refs" && -z "$target_main" ]]; then
  platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.SYNC_TARGET_MAIN_MISSING" "Kho đích không trống nhưng không có branch main. Từ chối tự tạo main."
fi

work_dir="$(mktemp -d /tmp/platform-repository-sync.XXXXXX)"
bare_repo="$work_dir/repo.git"
git init --bare -q "$bare_repo"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

source_ref="refs/platform/repository-sync/source-main"
target_ref="refs/platform/repository-sync/target-main"
verify_ref="refs/platform/repository-sync/verify-main"
repo_git "$source_effective" --git-dir="$bare_repo" fetch --no-tags "$source_effective" "refs/heads/main:$source_ref" >/dev/null
source_tree="$(git --git-dir="$bare_repo" rev-parse "$source_ref^{tree}")"

relation="EMPTY"
action="CREATE TARGET MAIN"
if [[ -n "$target_main" ]]; then
  repo_git "$target_effective" --git-dir="$bare_repo" fetch --no-tags "$target_effective" "refs/heads/main:$target_ref" >/dev/null
  if [[ "$source_main" == "$target_main" ]]; then
    relation="EQUAL"
    action="NO CHANGE"
  elif git --git-dir="$bare_repo" merge-base --is-ancestor "$target_ref" "$source_ref" >/dev/null 2>&1; then
    relation="TARGET BEHIND SOURCE"
    action="FAST-FORWARD TARGET"
  elif git --git-dir="$bare_repo" merge-base --is-ancestor "$source_ref" "$target_ref" >/dev/null 2>&1; then
    cat <<EOF
=========================================================
REPOSITORY SYNC CHECK — BLOCKED
=========================================================
Source repo  : $source_repo
Source main  : $source_main
Target repo  : $target_repo
Target main  : $target_main
Relation     : TARGET AHEAD OF SOURCE
=========================================================
EOF
    platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.SYNC_TARGET_AHEAD" "Kho đích đang đi trước kho nguồn; từ chối ghi đè hoặc sync ngược."
  else
    cat <<EOF
=========================================================
REPOSITORY SYNC CHECK — BLOCKED
=========================================================
Source repo  : $source_repo
Source main  : $source_main
Target repo  : $target_repo
Target main  : $target_main
Relation     : DIVERGED
=========================================================
EOF
    platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.SYNC_DIVERGED" "Hai branch main đã diverged; từ chối force-push hoặc tự merge."
  fi
fi

commits_to_sync=0
files_changed=0
commit_range=""
diff_from=""
if [[ "$relation" == "EMPTY" ]]; then
  commits_to_sync="$(git --git-dir="$bare_repo" rev-list --count "$source_ref")"
  files_changed="$(git --git-dir="$bare_repo" ls-tree -r --name-only "$source_ref" | wc -l | tr -d ' ')"
elif [[ "$relation" == "TARGET BEHIND SOURCE" ]]; then
  commit_range="$target_ref..$source_ref"
  diff_from="$target_ref"
  commits_to_sync="$(git --git-dir="$bare_repo" rev-list --count "$commit_range")"
  files_changed="$(git --git-dir="$bare_repo" diff --name-only "$target_ref" "$source_ref" | wc -l | tr -d ' ')"
fi

cat <<EOF
=========================================================
REPOSITORY SYNC PLAN
=========================================================
Source repo  : $source_repo
Source main  : $source_main
Source tree  : $source_tree
Target repo  : $target_repo
Target main  : ${target_main:-<EMPTY>}
Relation     : $relation
Direction    : SOURCE -> TARGET
Branch       : main
Action       : $action
Commits sync : $commits_to_sync
Files change : $files_changed
Force push   : NO
Site source  : NO CHANGE
Site origin  : NO CHANGE
Inventory    : NO CHANGE
Deploy       : NO
Database     : NO
Containers   : NO
=========================================================
EOF

if (( commits_to_sync > 0 )); then
  echo
  echo '----- COMMITS SẼ ĐỒNG BỘ (tối đa 30 commit mới nhất) -----'
  if [[ "$relation" == "EMPTY" ]]; then
    git --git-dir="$bare_repo" log --oneline --decorate=no -30 "$source_ref"
  else
    git --git-dir="$bare_repo" log --oneline --decorate=no -30 "$commit_range"
  fi
  if (( commits_to_sync > 30 )); then
    printf '... và %d commit khác.\n' "$((commits_to_sync - 30))"
  fi
fi

if (( files_changed > 0 )); then
  echo
  echo '----- FILES SẼ THAY ĐỔI (tối đa 50 file) -----'
  if [[ "$relation" == "EMPTY" ]]; then
    git --git-dir="$bare_repo" ls-tree -r --name-only "$source_ref" | head -50 | sed 's/^/A\t/'
  else
    git --git-dir="$bare_repo" diff --name-status "$diff_from" "$source_ref" | head -50
  fi
  if (( files_changed > 50 )); then
    printf '... và %d file khác.\n' "$((files_changed - 50))"
  fi
fi

if (( dry_run == 1 )); then
  echo "[DRY-RUN] Điều kiện sync hợp lệ; chưa có repository nào bị thay đổi."
  exit 0
fi
[[ "$yes" -eq 1 ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.CONFIRMATION_REQUIRED" "Thiếu --yes. Hãy chạy --dry-run trước."

if [[ "$relation" == "EQUAL" ]]; then
  echo "[OK] Hai repository đã đồng bộ; không cần push."
  exit 0
fi

if ! repo_git "$target_effective" --git-dir="$bare_repo" push "$target_effective" "$source_ref:refs/heads/main" >/dev/null; then
  platform_die "$PLATFORM_EXIT_OPERATION" "GIT.SYNC_PUSH_FAILED" "Push source/main -> target/main thất bại. Không force-push được thực hiện."
fi

verified_main="$(repo_git "$target_effective" ls-remote --heads "$target_effective" refs/heads/main | awk 'NR==1 {print $1}')"
[[ "$verified_main" == "$source_main" ]] || platform_die "$PLATFORM_EXIT_OPERATION" "GIT.SYNC_SHA_MISMATCH" "Verify target/main SHA sau sync thất bại."
repo_git "$target_effective" --git-dir="$bare_repo" fetch --no-tags "$target_effective" "refs/heads/main:$verify_ref" >/dev/null
verified_tree="$(git --git-dir="$bare_repo" rev-parse "$verify_ref^{tree}")"
[[ "$verified_tree" == "$source_tree" ]] || platform_die "$PLATFORM_EXIT_OPERATION" "GIT.SYNC_TREE_MISMATCH" "Verify target/main source tree sau sync thất bại."

printf '[OK] Repository sync thành công: %s main -> %s main\n' "$source_repo" "$target_repo"
printf '[OK] Verified SHA: %s\n' "$source_main"
printf '[OK] Verified tree: %s\n' "$source_tree"
printf '[OK] Site/Inventory/deploy/database/container không bị thay đổi.\n'
