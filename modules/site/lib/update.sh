#!/usr/bin/env bash

site_update_local_changes() {
  local project_path="$1"
  [[ -d "$project_path/.git" ]] || die "Site không phải Git working tree: $project_path"
  git -C "$project_path" status --porcelain --untracked-files=no
}

site_update_storage_changed_files() {
  local project_path="$1" old_commit="$2" new_commit="$3"
  git -C "$project_path" diff \
    --name-only \
    --diff-filter=AM \
    --no-renames \
    "$old_commit" "$new_commit" -- storage/app/public/
}

site_update_storage_write_file() {
  local key="$1" project_path="$2" strategy="$3" relative_path="$4"
  local source_file="$project_path/$relative_path"
  local storage_relative="${relative_path#storage/app/public/}"

  [[ "$relative_path" == storage/app/public/* ]] || die "Storage sync path không hợp lệ: $relative_path"
  [[ -n "$storage_relative" && -f "$source_file" ]] || die "Storage sync source không tồn tại: $relative_path"

  case "$strategy" in
    repository)
      local compose_file
      compose_file="$(inventory_get_field "$key" compose_file 2>/dev/null || true)"
      compose_file="${compose_file:-compose.yaml}"
      cat "$source_file" | site_create_repository_compose "$project_path" "$compose_file" \
        exec -T app sh -c '
          set -e
          relative="$1"
          destination="storage/app/public/$relative"
          mkdir -p "$(dirname "$destination")"
          cat > "$destination"
          chown www-data:www-data "$destination" 2>/dev/null || true
          chmod 664 "$destination" 2>/dev/null || true
        ' sh "$storage_relative"
      ;;
    platform|"")
      cat "$source_file" | deploy_compose "$project_path" \
        exec -T app sh -c '
          set -e
          relative="$1"
          destination="storage/app/public/$relative"
          mkdir -p "$(dirname "$destination")"
          cat > "$destination"
          chown www-data:www-data "$destination" 2>/dev/null || true
          chmod 664 "$destination" 2>/dev/null || true
        ' sh "$storage_relative"
      ;;
    *) die "Runtime strategy không hỗ trợ storage sync: $strategy" ;;
  esac
}

site_update_sync_git_public_storage() {
  local key="$1" project_path="$2" strategy="$3" old_commit="$4" new_commit="$5"
  local -a files=()
  local relative_path

  mapfile -t files < <(site_update_storage_changed_files "$project_path" "$old_commit" "$new_commit")
  [[ "${#files[@]}" -gt 0 ]] || return 0

  echo "[UPDATE STORAGE] Đồng bộ ${#files[@]} file Git-managed vào persistent storage"
  for relative_path in "${files[@]}"; do
    [[ -n "$relative_path" ]] || continue
    echo "[UPDATE STORAGE] $relative_path"
    site_update_storage_write_file "$key" "$project_path" "$strategy" "$relative_path"
  done
}

site_update_record_commit() {
  local key="$1" old_commit="$2" new_commit="$3" branch="$4" repo="$5"
  inventory_init

  python3 - "$(inventory_file)" "$key" "$old_commit" "$new_commit" "$branch" "$repo" <<'PY'
import datetime,json,os,sys
path,key,old_commit,new_commit,branch,repo=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
site=None
for item in d.get("sites",[]):
    if key in (str(item.get("name","")),str(item.get("domain","")),str(item.get("path",""))):
        site=item
        break
if site is None:
    raise SystemExit("site not found")
site["previous_commit"]=old_commit
site["commit"]=new_commit
site["branch"]=branch
site["repo"]=repo
site["status"]="active"
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
site["last_updated_at"]=now
site["last_synced_at"]=now
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2)
    f.write("\n")
os.replace(tmp,path)
PY
}

site_update_deploy() {
  local key="$1" project_path="$2" strategy="$3" timeout="$4"

  case "$strategy" in
    repository)
      local compose_file dockerfile http_port
      compose_file="$(inventory_get_field "$key" compose_file 2>/dev/null || true)"
      dockerfile="$(inventory_get_field "$key" dockerfile 2>/dev/null || true)"
      http_port="$(inventory_get_field "$key" http_port)"
      compose_file="${compose_file:-compose.yaml}"
      dockerfile="${dockerfile:-Dockerfile}"

      site_create_repository_validate_contract "$project_path" "$dockerfile" "$compose_file"
      site_create_repository_prepare "$project_path" "$compose_file" "$http_port" "$timeout"
      # Intentionally use the base repository finalize from create-strategy.sh.
      # create-seed-policy.sh is NOT sourced by site update, so update never seeds.
      site_create_repository_finalize "$project_path" "$compose_file"
      site_create_repository_health "$project_path" "$compose_file"
      ;;
    platform|"")
      deploy_run "$key" "--timeout=$timeout"
      ;;
    *) die "Runtime strategy không hỗ trợ update: $strategy" ;;
  esac
}

site_update() {
  require_root
  require_command git
  require_command python3

  local key="${1:-}"; shift || true
  local dry_run=0 auto_yes=0 timeout=120 arg

  [[ -n "$key" ]] || die "USAGE: platform site update <site> [--dry-run] [--yes] [--timeout=N]"

  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      --timeout=*) timeout="${arg#*=}" ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "--timeout phải là số."

  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"

  local name project_path branch current_branch repo actual_repo strategy old_commit new_commit dirty
  name="$(inventory_get_field "$key" name)"
  project_path="$(inventory_get_field "$key" path)"
  branch="$(inventory_get_field "$key" branch)"
  repo="$(inventory_get_field "$key" repo)"
  strategy="$(inventory_get_field "$key" runtime_strategy 2>/dev/null || true)"
  strategy="${strategy:-platform}"

  [[ -d "$project_path" ]] || die "Project path không tồn tại: $project_path"
  [[ -d "$project_path/.git" ]] || die "Site không phải Git working tree: $project_path"

  current_branch="$(git -C "$project_path" branch --show-current)"
  [[ -n "$current_branch" ]] || die "Git đang detached HEAD; từ chối update."
  [[ -n "$branch" ]] || branch="$current_branch"
  [[ "$current_branch" == "$branch" ]] || die "Branch local [$current_branch] khác Inventory [$branch]."

  actual_repo="$(git -C "$project_path" remote get-url origin 2>/dev/null || true)"
  [[ -n "$actual_repo" ]] || die "Git repository thiếu remote origin."
  if [[ -n "$repo" && "$actual_repo" != "$repo" ]]; then
    die "Remote origin khác Inventory. origin=$actual_repo inventory=$repo"
  fi
  repo="${repo:-$actual_repo}"

  old_commit="$(git -C "$project_path" rev-parse HEAD)"
  dirty="$(site_update_local_changes "$project_path")"

  echo "[UPDATE] Fetch origin/$branch"
  git -C "$project_path" fetch --prune origin "$branch"
  new_commit="$(git -C "$project_path" rev-parse "origin/$branch")"

  echo "Site        : $name"
  echo "Strategy    : $strategy"
  echo "Repository  : $repo"
  echo "Branch      : $branch"
  echo "Old commit  : $old_commit"
  echo "New commit  : $new_commit"

  if [[ -n "$dirty" ]]; then
    echo "Local changes:"
    printf '%s\n' "$dirty"
    warn "Managed production policy: GitHub origin/$branch là source of truth."
    if [[ "$dry_run" -eq 1 ]]; then
      echo "[DRY-RUN] Local tracked changes sẽ bị loại bỏ bằng git reset --hard origin/$branch."
    else
      warn "Local tracked changes sẽ bị loại bỏ trước deploy."
    fi
  fi

  if [[ "$old_commit" != "$new_commit" ]]; then
    git -C "$project_path" merge-base --is-ancestor "$old_commit" "$new_commit" \
      || die "Remote không phải fast-forward từ commit hiện tại; từ chối update tự động."
  fi

  local -a storage_changes=()
  if [[ "$old_commit" != "$new_commit" ]]; then
    mapfile -t storage_changes < <(site_update_storage_changed_files "$project_path" "$old_commit" "$new_commit")
    if [[ "${#storage_changes[@]}" -gt 0 ]]; then
      echo "Git storage : ${#storage_changes[@]} file(s) sẽ đồng bộ vào persistent storage"
      printf '  - %s\n' "${storage_changes[@]}"
    fi
  fi

  if [[ "$old_commit" == "$new_commit" && -z "$dirty" ]]; then
    success "Site đã ở commit mới nhất; không cần deploy: $name"
    return 0
  fi

  if [[ "$dry_run" -eq 1 ]]; then
    if [[ "$old_commit" == "$new_commit" ]]; then
      echo "[DRY-RUN] Commit đã mới nhất nhưng working tree dirty; sẽ reset về origin/$branch và deploy lại; không db:seed."
    else
      echo "[DRY-RUN] Sẽ reset source về origin/$branch ($old_commit -> $new_commit) và deploy lại; không db:seed."
    fi
    [[ "${#storage_changes[@]}" -eq 0 ]] || echo "[DRY-RUN] File Git-managed trong storage/app/public sẽ được đồng bộ sau deploy."
    return 0
  fi

  [[ "$auto_yes" -eq 1 ]] || site_confirm "Update site $name từ GitHub? Local tracked changes (nếu có) sẽ bị loại bỏ." || die "Đã hủy."

  trap 'rc=$?; if [[ $rc -ne 0 ]]; then
          warn "Update/deploy thất bại. Git hiện có thể đã ở commit target."
          warn "OLD_COMMIT=$old_commit"
          warn "TARGET_COMMIT=$new_commit"
          warn "Không tự git reset rollback vì migration có thể đã chạy; cần đánh giá rollback trước."
        fi
        exit $rc' ERR

  if [[ -n "$dirty" ]]; then
    echo "[UPDATE] Discard local tracked changes; reset --hard origin/$branch"
  else
    echo "[UPDATE] Sync source exactly to origin/$branch"
  fi
  git -C "$project_path" reset --hard "origin/$branch"

  site_update_deploy "$name" "$project_path" "$strategy" "$timeout"
  if [[ "$old_commit" != "$new_commit" ]]; then
    site_update_sync_git_public_storage "$name" "$project_path" "$strategy" "$old_commit" "$new_commit"
  fi

  local deployed_commit
  deployed_commit="$(git -C "$project_path" rev-parse HEAD)"
  [[ "$deployed_commit" == "$new_commit" ]] || die "Commit sau deploy không khớp target."

  site_update_record_commit "$name" "$old_commit" "$deployed_commit" "$branch" "$repo"
  trap - ERR

  success "Update site thành công: $name"
  echo "COMMIT: $old_commit -> $deployed_commit"
}
