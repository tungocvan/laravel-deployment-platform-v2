#!/usr/bin/env bash

# Repository access diagnostics are intentionally isolated from site state:
# probes use a temporary ref only, and generated private keys are never printed.
ui_repo_access_parse_github() {
  local repo="$1"
  if [[ "$repo" =~ ^git@github\.com:([^/]+)/([^/]+)$ ]]; then
    UI_REPO_OWNER="${BASH_REMATCH[1]}"
    UI_REPO_NAME="${BASH_REMATCH[2]}"
    UI_REPO_NAME="${UI_REPO_NAME%.git}"
    [[ -n "$UI_REPO_OWNER" && -n "$UI_REPO_NAME" ]]
    return
  fi
  if [[ "$repo" =~ ^https://github\.com/([^/]+)/([^/]+)/?$ ]]; then
    UI_REPO_OWNER="${BASH_REMATCH[1]}"
    UI_REPO_NAME="${BASH_REMATCH[2]}"
    UI_REPO_NAME="${UI_REPO_NAME%.git}"
    [[ -n "$UI_REPO_OWNER" && -n "$UI_REPO_NAME" ]]
    return
  fi
  return 1
}

ui_repo_access_probe() {
  local repo="$1" ssh_command="${2:-}"
  local tmp probe_ref read_exit push_exit delete_exit
  UI_REPO_ACCESS_READ=0
  UI_REPO_ACCESS_WRITE=0
  UI_REPO_ACCESS_DELETE=0
  UI_REPO_ACCESS_DETAIL=""

  set +e
  if [[ -n "$ssh_command" ]]; then
    GIT_SSH_COMMAND="$ssh_command" git ls-remote "$repo" >/dev/null 2>&1
  else
    git ls-remote "$repo" >/dev/null 2>&1
  fi
  read_exit=$?
  set -e
  if [[ "$read_exit" -ne 0 ]]; then
    UI_REPO_ACCESS_DETAIL="READ denied/unreachable"
    return 1
  fi
  UI_REPO_ACCESS_READ=1

  tmp="$(mktemp -d /tmp/platform-repo-access.XXXXXX)"
  trap 'rm -rf "$tmp"' RETURN
  git -C "$tmp" init -q
  git -C "$tmp" config user.name "Platform Repository Access Probe"
  git -C "$tmp" config user.email "platform-probe@localhost"
  printf 'platform repository access probe\n' >"$tmp/.platform-probe"
  git -C "$tmp" add .platform-probe
  git -C "$tmp" commit -qm "chore: repository access probe"
  probe_ref="refs/platform/write-probe/access-$(date +%s)-$$"

  set +e
  if [[ -n "$ssh_command" ]]; then
    GIT_SSH_COMMAND="$ssh_command" git -C "$tmp" push "$repo" "HEAD:$probe_ref" >/dev/null 2>&1
  else
    git -C "$tmp" push "$repo" "HEAD:$probe_ref" >/dev/null 2>&1
  fi
  push_exit=$?
  set -e
  if [[ "$push_exit" -ne 0 ]]; then
    UI_REPO_ACCESS_DETAIL="READ ok; WRITE denied"
    return 1
  fi
  UI_REPO_ACCESS_WRITE=1

  set +e
  if [[ -n "$ssh_command" ]]; then
    GIT_SSH_COMMAND="$ssh_command" git -C "$tmp" push "$repo" ":$probe_ref" >/dev/null 2>&1
  else
    git -C "$tmp" push "$repo" ":$probe_ref" >/dev/null 2>&1
  fi
  delete_exit=$?
  set -e
  if [[ "$delete_exit" -ne 0 ]]; then
    UI_REPO_ACCESS_DETAIL="READ/WRITE ok; DELETE probe ref denied. Hãy xóa thủ công $probe_ref"
    return 1
  fi
  UI_REPO_ACCESS_DELETE=1
  UI_REPO_ACCESS_DETAIL="READ + WRITE + DELETE ok"
  return 0
}

ui_repo_access_show_result() {
  echo
  ui_line
  echo " REPOSITORY ACCESS RESULT"
  ui_line
  printf 'Read access   : %s\n' "$([[ "$UI_REPO_ACCESS_READ" -eq 1 ]] && echo OK || echo DENIED)"
  printf 'Write access  : %s\n' "$([[ "$UI_REPO_ACCESS_WRITE" -eq 1 ]] && echo OK || echo DENIED)"
  printf 'Delete access : %s\n' "$([[ "$UI_REPO_ACCESS_DELETE" -eq 1 ]] && echo OK || echo DENIED)"
  printf 'Detail        : %s\n' "${UI_REPO_ACCESS_DETAIL:-N/A}"
  ui_line
}

ui_repo_access_existing_owner_alias() {
  local owner="$1" name="$2" candidate effective_host alias_repo
  UI_REPO_ACCESS_EXISTING_ALIAS=""
  UI_REPO_ACCESS_EXISTING_REPO=""

  # First try the canonical owner alias used by Platform installations,
  # e.g. github-tungocvan. Then try a repository-specific alias if it exists.
  for candidate in "github-$owner" "github-$owner-$name"; do
    effective_host="$(ssh -G "$candidate" 2>/dev/null | awk '$1=="hostname" {print $2; exit}')"
    [[ "$effective_host" == "github.com" ]] || continue
    alias_repo="git@${candidate}:${owner}/${name}.git"
    if git ls-remote "$alias_repo" >/dev/null 2>&1; then
      UI_REPO_ACCESS_EXISTING_ALIAS="$candidate"
      UI_REPO_ACCESS_EXISTING_REPO="$alias_repo"
      return 0
    fi
  done
  return 1
}

ui_repo_access_generate_key() {
  local repo="$1" owner="$2" name="$3"
  local ssh_dir key_base key_file alias config_file
  ssh_dir="${HOME:-/root}/.ssh"
  mkdir -p "$ssh_dir"
  chmod 700 "$ssh_dir"

  key_base="github_${owner}_${name}_ed25519"
  key_base="$(printf '%s' "$key_base" | tr -cs 'A-Za-z0-9_.-' '_')"
  key_file="$ssh_dir/$key_base"
  if [[ -e "$key_file" || -e "$key_file.pub" ]]; then
    key_file="${key_file}_$(date +%Y%m%d_%H%M%S)"
  fi
  alias="github-${owner}-${name}"
  alias="$(printf '%s' "$alias" | tr -cs 'A-Za-z0-9_.-' '-')"
  config_file="$ssh_dir/config"

  echo
  echo "[INFO] Tạo SSH key riêng cho repository."
  echo "[INFO] Private key: $key_file (KHÔNG hiển thị)"
  ssh-keygen -t ed25519 -N '' -C "platform:${owner}/${name}" -f "$key_file" >/dev/null
  chmod 600 "$key_file"
  chmod 644 "$key_file.pub"

  touch "$config_file"
  chmod 600 "$config_file"
  if ! grep -qE "^Host[[:space:]]+$alias([[:space:]]|$)" "$config_file"; then
    cat >>"$config_file" <<EOF

Host $alias
    HostName github.com
    User git
    IdentityFile $key_file
    IdentitiesOnly yes
EOF
  fi

  UI_REPO_ACCESS_KEY_FILE="$key_file"
  UI_REPO_ACCESS_ALIAS="$alias"
  UI_REPO_ACCESS_ALIAS_REPO="git@${alias}:${owner}/${name}.git"

  echo
  ui_line
  echo " SSH PUBLIC KEY — THÊM KEY NÀY VÀO GITHUB"
  ui_line
  cat "$key_file.pub"
  ui_line
  echo
  echo "GitHub account key : Settings -> SSH and GPG keys -> New SSH key"
  echo "Hoặc deploy key    : Repository -> Settings -> Deploy keys -> Add deploy key"
  echo "                     Nếu dùng Deploy key, bật Allow write access."
  echo
  echo "SSH alias đã tạo   : $alias"
  echo "Repository URL mới : $UI_REPO_ACCESS_ALIAS_REPO"
  echo
  echo "[IMPORTANT] Platform chỉ tạo key/SSH transport; quyền GitHub chỉ có hiệu lực sau khi bạn thêm PUBLIC KEY ở trên vào GitHub."
}

ui_flow_repository_access() {
  local repo owner name ssh_command=""
  ui_section "KIỂM TRA QUYỀN REPOSITORY / SSH KEY SETUP"
  echo "Kiểm tra an toàn:"
  echo "  - READ bằng git ls-remote"
  echo "  - WRITE bằng ref tạm refs/platform/write-probe/..."
  echo "  - DELETE bằng cách xóa đúng ref tạm vừa tạo"
  echo "  - Nếu credential mặc định fail, Platform thử SSH alias owner đã có trước"
  echo "  - Không sửa main, tag, source site, Inventory, deploy hoặc database"
  echo

  repo="$(ui_prompt "Địa chỉ Git repository")"
  [[ -n "$repo" ]] || { echo "[ERROR] Repository bắt buộc."; ui_pause; return; }

  if ui_repo_access_probe "$repo"; then
    ui_repo_access_show_result
    echo "[OK] Repository có đủ quyền READ + WRITE + DELETE bằng credential hiện tại."
    ui_pause
    return 0
  fi
  ui_repo_access_show_result

  if ! ui_repo_access_parse_github "$repo"; then
    echo "[WARN] Tự động nhận diện SSH identity hiện chỉ hỗ trợ URL github.com."
    echo "[INFO] Hãy cấu hình credential của Git server này thủ công rồi kiểm tra lại."
    ui_pause
    return 1
  fi
  owner="$UI_REPO_OWNER"
  name="$UI_REPO_NAME"

  if ui_repo_access_existing_owner_alias "$owner" "$name"; then
    echo
    echo "[INFO] Phát hiện SSH alias đã có cho owner: $UI_REPO_ACCESS_EXISTING_ALIAS"
    echo "[INFO] Kiểm tra lại bằng: $UI_REPO_ACCESS_EXISTING_REPO"
    if ui_repo_access_probe "$UI_REPO_ACCESS_EXISTING_REPO"; then
      ui_repo_access_show_result
      echo "[OK] Repository có đủ READ + WRITE + DELETE bằng SSH alias hiện có."
      echo "[INFO] Không cần tạo SSH key mới."
      ui_pause
      return 0
    fi
    ui_repo_access_show_result
  fi

  echo
  echo "Repository vẫn chưa đủ quyền ghi/xóa sau khi thử credential/alias hiện có."
  ui_yesno "Tạo SSH key riêng cho ${owner}/${name} để cấu hình quyền?" "N" || { ui_pause; return 0; }

  command -v ssh-keygen >/dev/null 2>&1 || {
    echo "[ERROR] Không có ssh-keygen trên server."
    ui_pause
    return 1
  }
  ui_repo_access_generate_key "$repo" "$owner" "$name"

  echo
  echo "Sau khi bạn thêm PUBLIC KEY vào GitHub, có thể kiểm tra lại ngay."
  if ui_yesno "Đã cập nhật key trên GitHub và muốn kiểm tra lại bây giờ?" "N"; then
    ssh_command="ssh -i $UI_REPO_ACCESS_KEY_FILE -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    if ui_repo_access_probe "$UI_REPO_ACCESS_ALIAS_REPO" "$ssh_command"; then
      ui_repo_access_show_result
      echo "[OK] Key mới đã có đủ READ + WRITE + DELETE."
      echo "[INFO] Khi cần dùng key riêng này, dùng repository URL: $UI_REPO_ACCESS_ALIAS_REPO"
    else
      ui_repo_access_show_result
      echo "[WARN] Key mới vẫn chưa đủ quyền. Kiểm tra key đã được thêm đúng GitHub account/repository và có write access."
    fi
  fi
  ui_pause
}
