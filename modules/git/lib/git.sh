#!/usr/bin/env bash

platform_git_require() {
  require_command git
}

platform_git_canonical_path() {
  local path="${1:-}"
  [[ -n "$path" ]] || die "Git path rỗng."
  [[ -e "$path" ]] || die "Git path không tồn tại: $path"
  readlink -f "$path"
}

platform_git_normalize_safe_directories() {
  platform_git_require

  local values=() value
  while IFS= read -r value; do
    [[ -n "$value" ]] || continue
    values+=("$value")
  done < <(git config --global --get-all safe.directory 2>/dev/null || true)

  # Remove every current entry, including reset markers.
  git config --global --unset-all safe.directory >/dev/null 2>&1 || true

  # Re-add unique non-empty values while preserving order.
  local seen="" canonical
  for value in "${values[@]}"; do
    canonical="$value"
    if [[ "$value" != "*" && -e "$value" ]]; then
      canonical="$(readlink -f "$value")"
    fi

    case $'\n'"$seen"$'\n' in
      *$'\n'"$canonical"$'\n'*) continue ;;
    esac

    git config --global --add safe.directory "$canonical"
    seen+="${canonical}"$'\n'
  done
}

platform_git_trust() {
  platform_git_require

  local path
  path="$(platform_git_canonical_path "${1:-}")"

  # Important: an empty safe.directory entry resets earlier values.
  platform_git_normalize_safe_directories

  if ! git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$path"; then
    git config --global --add safe.directory "$path"
  fi

  # Defensive check: ensure no empty reset marker remains after write.
  if git config --global --get-all safe.directory 2>/dev/null | grep -qx ''; then
    platform_git_normalize_safe_directories
    git config --global --get-all safe.directory 2>/dev/null | grep -Fxq "$path" \
      || git config --global --add safe.directory "$path"
  fi
}

platform_git_is_repo() {
  local path="${1:-}"
  [[ -n "$path" && -d "$path/.git" ]]
}

platform_git_verify() {
  platform_git_require

  local path
  path="$(platform_git_canonical_path "${1:-}")"

  [[ -d "$path/.git" ]] || die "Không phải Git working tree: $path"

  platform_git_trust "$path"

  git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null | grep -qx true \
    || die "Git working tree không hợp lệ: $path"

  git -C "$path" rev-parse HEAD >/dev/null 2>&1 \
    || die "Không đọc được Git HEAD: $path"
}

platform_git_commit() {
  local path="${1:-}"
  platform_git_verify "$path"
  git -C "$(platform_git_canonical_path "$path")" rev-parse HEAD
}

platform_git_commit_short() {
  local path="${1:-}"
  platform_git_verify "$path"
  git -C "$(platform_git_canonical_path "$path")" rev-parse --short HEAD
}

platform_git_branch() {
  local path="${1:-}"
  platform_git_verify "$path"
  local branch
  branch="$(git -C "$(platform_git_canonical_path "$path")" branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] && printf '%s\n' "$branch" || printf 'DETACHED\n'
}

platform_git_remote() {
  local path="${1:-}"
  platform_git_verify "$path"
  git -C "$(platform_git_canonical_path "$path")" remote get-url origin 2>/dev/null || true
}

platform_git_info() {
  local path="${1:-}"
  platform_git_verify "$path"

  local canonical branch commit remote
  canonical="$(platform_git_canonical_path "$path")"
  branch="$(platform_git_branch "$canonical")"
  commit="$(platform_git_commit "$canonical")"
  remote="$(platform_git_remote "$canonical")"

  python3 - "$canonical" "$branch" "$commit" "$remote" <<'PY'
import json,sys
path,branch,commit,remote=sys.argv[1:]
print(json.dumps({
    "path": path,
    "branch": branch,
    "commit": commit,
    "remote": remote or None,
    "trusted": True,
    "valid": True
}, ensure_ascii=False, indent=2))
PY
}

platform_git_copy_metadata() {
  platform_git_require
  require_command rsync

  local source destination
  source="$(platform_git_canonical_path "${1:-}")"
  destination="${2:-}"

  [[ -n "$destination" ]] || die "Thiếu destination Git path."
  [[ -d "$source/.git" ]] || die "Source không có .git: $source"
  [[ -d "$destination" ]] || die "Destination path không tồn tại: $destination"
  [[ ! -e "$destination/.git" ]] || die "Destination đã có .git: $destination"

  platform_git_verify "$source"

  rsync -a "$source/.git/" "$destination/.git/"

  platform_git_trust "$destination"
  platform_git_verify "$destination"

  local src_head dst_head
  src_head="$(git -C "$source" rev-parse HEAD)"
  dst_head="$(git -C "$destination" rev-parse HEAD)"

  [[ "$src_head" == "$dst_head" ]] \
    || die "Git metadata copy mismatch: source HEAD != destination HEAD"
}

platform_git_clone() {
  platform_git_require

  local repo="${1:-}" destination="${2:-}" branch="${3:-main}"
  [[ -n "$repo" && -n "$destination" ]] \
    || die "USAGE: platform_git_clone <repo> <destination> [branch]"
  [[ ! -e "$destination" ]] || die "Destination đã tồn tại: $destination"

  git clone --branch "$branch" --single-branch "$repo" "$destination"
  platform_git_trust "$destination"
  platform_git_verify "$destination"
}


# Resolve a GitHub repository's existing SSH alias without changing origin,
# Inventory, SSH configuration or private keys. Read probes never write refs.
platform_git_find_accessible_alias() {
  local repo="${1:-}" owner name candidate effective_host alias_repo
  [[ "$repo" =~ ^git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)\.git$ ]] || return 1
  owner="${BASH_REMATCH[1]}"
  name="${BASH_REMATCH[2]}"
  for candidate in "github-$owner" "github-$owner-$name"; do
    effective_host="$(ssh -G "$candidate" 2>/dev/null | awk '$1=="hostname" {print $2; exit}')" || continue
    [[ "$effective_host" == "github.com" ]] || continue
    alias_repo="git@${candidate}:${owner}/${name}.git"
    if GIT_TERMINAL_PROMPT=0 git ls-remote "$alias_repo" HEAD >/dev/null 2>&1; then
      printf '%s\n' "$alias_repo"
      return 0
    fi
  done
  return 1
}

# Return canonical URL when readable, otherwise a verified existing alias.
platform_git_resolve_read_url() {
  local repo="${1:-}" alias_repo
  [[ -n "$repo" ]] || return 1
  if [[ ! "$repo" =~ ^git@github\.com:[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$ ]]; then
    printf '%s\n' "$repo"
    return 0
  fi
  if GIT_TERMINAL_PROMPT=0 git ls-remote "$repo" HEAD >/dev/null 2>&1; then
    printf '%s\n' "$repo"
    return 0
  fi
  alias_repo="$(platform_git_find_accessible_alias "$repo")" || return 1
  printf '%s\n' "$alias_repo"
}

# Rewrite transport for one Git invocation only; never mutate remote or config.
platform_git_transport() {
  local canonical="${1:-}" resolved="${2:-}"
  shift 2
  if [[ "$canonical" == "$resolved" ]]; then
    git "$@"
  else
    git -c "url.${resolved}.insteadOf=${canonical}" "$@"
  fi
}
