#!/usr/bin/env bash
# Prepare a NEW GitHub repository without changing the site's origin or Inventory.
# Sourced by bootstrap-remote.sh after platform bootstrap and option parsing.
platform_prepare_repository_only() {
  local site="$1" target="$2" dry="$3" confirmed="$4"
  local slug owner name target_url path branch current_repo site_head source_head verify_sha
  if [[ "$target" =~ ^git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)(\.git)?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[2]%.git}"
  elif [[ "$target" =~ ^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$ ]]; then
    owner="${BASH_REMATCH[1]}"
    name="${BASH_REMATCH[2]%.git}"
  else
    platform_die "$PLATFORM_EXIT_USAGE" "GIT.INVALID_TARGET" "Chỉ hỗ trợ owner/name hoặc git@github.com:owner/name.git."
  fi
  [[ "$owner" == "tungocvan" ]] || platform_die "$PLATFORM_EXIT_USAGE" "GIT.OWNER_UNSUPPORTED" "Prepare-only hiện chỉ hỗ trợ owner tungocvan với SSH identity được cấu hình."
  slug="$owner/$name"
  target_url="git@github.com:$slug.git"
  path="$(inventory_get_field "$site" path 2>/dev/null || true)"
  [[ -n "$path" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.SITE_NOT_FOUND" "Site không tồn tại."
  platform_git_verify "$path"
  branch="$(platform_git_branch "$path")"
  [[ "$branch" == main ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.MAIN_BRANCH_REQUIRED" "Site phải ở branch main."
  current_repo="$(platform_git_remote "$path")"
  [[ -n "$current_repo" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.ORIGIN_MISSING" "Thiếu origin."
  [[ "$current_repo" != "$target_url" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.TARGET_EQUALS_CURRENT" "Không được bootstrap vào repository đang dùng."
  site_head="$(git -C "$path" rev-parse HEAD)"
  source_head="$(git ls-remote --heads "$current_repo" refs/heads/main | awk 'NR==1 {print $1}')"
  [[ -n "$source_head" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.CURRENT_MAIN_NOT_FOUND" "Không đọc được source/main."
  # The remote-tracking ref is fetched only for validation, and cleaned up on exit.
  local source_ref="refs/platform/repository-bootstrap/prepare-source-main"
  trap 'git -C "$path" update-ref -d "$source_ref" >/dev/null 2>&1 || true' EXIT
  git -C "$path" fetch --no-tags "$current_repo" "refs/heads/main:$source_ref" >/dev/null
  git -C "$path" merge-base --is-ancestor "$site_head" "$source_ref" || \
    platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.SITE_HEAD_NOT_IN_SOURCE_MAIN" "Site HEAD không thuộc source/main."
  local dirty
  dirty="$(git -C "$path" status --porcelain --untracked-files=all -- . ':(exclude).env' ':(exclude).docker-platform.env' ':(exclude)compose.queue.yaml' ':(exclude)compose.socket.yaml' ':(exclude)compose.scheduler.yaml')"
  [[ -z "$dirty" ]] || platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.WORKTREE_DIRTY" "Source worktree chưa sạch."
  command -v gh >/dev/null || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.GH_REQUIRED" "Cần GitHub CLI gh trên host."
  gh auth status >/dev/null 2>&1 || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.GH_AUTH_REQUIRED" "GitHub CLI chưa được xác thực."
  local api_status
  api_status="$(gh api -i "repos/$slug" 2>/dev/null | grep -m 1 "^HTTP/" || true)"
  if [[ "$api_status" == *" 200 "* ]]; then
    platform_die "$PLATFORM_EXIT_CONFLICT" "GIT.TARGET_ALREADY_EXISTS" "Repository đã tồn tại; không ghi đè."
  fi
  [[ "$api_status" == *" 404 "* ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.TARGET_CHECK_FAILED" "Không xác minh được trạng thái repository (HTTP: ${api_status:-unknown})."
  cat <<EOF
=========================================================
BOOTSTRAP PREPARE-ONLY PLAN
=========================================================
Site         : $site
Source repo  : $current_repo
Site HEAD    : $site_head
Source main  : $source_head
New repo     : $target_url
Visibility   : PRIVATE
Create       : YES (only after --yes)
Push         : source/main -> target/main (no force)
Site origin  : NO CHANGE
Inventory    : NO CHANGE
Deploy/DB    : NO CHANGE
Next step    : Menu 21 Update repository
=========================================================
EOF
  if (( dry == 1 )); then
    echo "[DRY-RUN] Repository chưa tồn tại; không tạo/push."
    return 0
  fi
  (( confirmed == 1 )) || platform_die "$PLATFORM_EXIT_USAGE" "GIT.CONFIRMATION_REQUIRED" "Cần --yes."
  # gh creates the repository only; no implicit local git remote or source mutation.
  gh repo create "$slug" --private || platform_die "$PLATFORM_EXIT_OPERATION" "GIT.CREATE_FAILED" "Không tạo được repository."
  local identity="${PLATFORM_TUNGOCVAN_GITHUB_IDENTITY_FILE:-/root/.ssh/github_tungocvan_ed25519}"
  [[ -r "$identity" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "GIT.IDENTITY_MISSING" "Thiếu SSH identity dành cho GitHub."
  if ! GIT_SSH_COMMAND="ssh -i $identity -o IdentitiesOnly=yes -o BatchMode=yes" git -C "$path" push "$target_url" "$source_ref:refs/heads/main"; then
    platform_die "$PLATFORM_EXIT_OPERATION" "GIT.PREPARE_PUSH_FAILED" "Repository đã tạo nhưng push thất bại. Không tự xóa repository."
  fi
  verify_sha="$(GIT_SSH_COMMAND="ssh -i $identity -o IdentitiesOnly=yes -o BatchMode=yes" git ls-remote --heads "$target_url" refs/heads/main | awk 'NR==1 {print $1}')"
  [[ "$verify_sha" == "$source_head" ]] || platform_die "$PLATFORM_EXIT_OPERATION" "GIT.PREPARE_VERIFY_FAILED" "Push đã chạy nhưng SHA không khớp; cần kiểm tra thủ công."
  echo "[OK] Repository mới đã có source/main: $verify_sha"
  echo "[OK] Site origin và Inventory giữ nguyên. Tiếp tục chức năng 21."
}
