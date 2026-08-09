#!/usr/bin/env bash

package_install() {
  require_root
  require_command unzip
  require_command sha256sum
  require_command python3

  local zip="${1:-}"
  [[ -f "$zip" ]] || die "Không tìm thấy ZIP: $zip"

  package_init_state

  local stage root id version target
  stage="$(mktemp -d /tmp/ldp-package.XXXXXX)"
  trap 'rm -rf "$stage"' RETURN

  unzip -q "$zip" -d "$stage"
  root="$(package_find_root "$stage")"

  [[ -f "$root/manifest.json" ]] || die "Thiếu manifest.json"
  [[ -f "$root/CHECKSUMS.sha256" ]] || die "Thiếu CHECKSUMS.sha256"
  [[ -x "$root/install.sh" ]] || die "Thiếu install.sh executable"

  (cd "$root" && sha256sum -c CHECKSUMS.sha256) || die "Checksum không hợp lệ."
  package_validate_manifest_basic "$root/manifest.json"

  id="$(package_manifest_field "$root/manifest.json" id)"
  version="$(package_manifest_field "$root/manifest.json" version)"
  target="$(package_manifest_field "$root/manifest.json" target)"

  [[ "$target" == "$PLATFORM_HOME" ]] || die "Package target không khớp PLATFORM_HOME."
  [[ ! -f "$(package_record_path "$id")" ]] || die "$id đã được cài. Dùng package upgrade."

  "$root/install.sh" --target="$PLATFORM_HOME"
  success "Đã cài $id $version"
}

package_upgrade() {
  require_root
  require_command unzip
  require_command sha256sum
  require_command python3

  local zip="${1:-}"
  [[ -f "$zip" ]] || die "Không tìm thấy ZIP: $zip"

  package_init_state

  local stage root id new_version target record old_version
  local tx_root tx_backup tx_old_record tx_history
  stage="$(mktemp -d /tmp/ldp-upgrade.XXXXXX)"
  trap 'rm -rf "$stage"' RETURN

  unzip -q "$zip" -d "$stage"
  root="$(package_find_root "$stage")"

  [[ -f "$root/manifest.json" ]] || die "Thiếu manifest.json"
  [[ -f "$root/CHECKSUMS.sha256" ]] || die "Thiếu CHECKSUMS.sha256"
  [[ -x "$root/install.sh" ]] || die "Thiếu install.sh executable"
  [[ -x "$root/verify.sh" ]] || die "Thiếu verify.sh executable"

  (cd "$root" && sha256sum -c CHECKSUMS.sha256) || die "Checksum không hợp lệ."
  package_validate_manifest_basic "$root/manifest.json"

  id="$(package_manifest_field "$root/manifest.json" id)"
  new_version="$(package_manifest_field "$root/manifest.json" version)"
  target="$(package_manifest_field "$root/manifest.json" target)"
  record="$(package_record_path "$id")"

  [[ "$target" == "$PLATFORM_HOME" ]] || die "Package target không khớp PLATFORM_HOME."
  [[ -f "$record" ]] || die "$id chưa được cài. Dùng package install."

  old_version="$(python3 - "$record" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:
    print(json.load(f).get("version",""))
PY
)"
  [[ "$old_version" != "$new_version" ]] || die "$id đang ở đúng version $new_version."

  info "Transactional upgrade $id: $old_version -> $new_version"

  tx_root="$(mktemp -d /tmp/ldp-tx.XXXXXX)"
  tx_backup="$tx_root/files"
  tx_old_record="$tx_root/old-record.json"
  tx_history="$(package_history_dir)/${id}.jsonl"

  mkdir -p "$tx_backup"
  cp -a "$record" "$tx_old_record"

  local payload_root
  payload_root="$(package_manifest_field "$root/manifest.json" payload_root)"
  [[ -d "$root/$payload_root" ]] || die "Payload root không tồn tại."

  while IFS= read -r -d '' src; do
    local rel dst
    rel="${src#$root/$payload_root/}"
    dst="$PLATFORM_HOME/$rel"
    if [[ -f "$dst" ]]; then
      mkdir -p "$tx_backup/$(dirname "$rel")"
      cp -a "$dst" "$tx_backup/$rel"
    fi
  done < <(find "$root/$payload_root" -type f -print0)

  cp -a "$record" "$tx_root/pre-install-record.json"

  platform_tx_begin "package-upgrade:$id" || die "Không thể bắt đầu package transaction."
  platform_tx_register package_tx_cleanup_root "$tx_root" || die "Không thể đăng ký transaction cleanup."
  platform_tx_register package_tx_restore_record "$tx_old_record" "$record" || die "Không thể đăng ký package record rollback."
  platform_tx_register package_tx_restore_files "$root/$payload_root" "$tx_backup" || die "Không thể đăng ký payload rollback."

  set +e
  PACKAGE_UPGRADE=1 \
  PACKAGE_UPGRADE_FROM="$old_version" \
  PACKAGE_TRANSACTION=1 \
  PACKAGE_TRANSACTION_ROOT="$tx_root" \
  "$root/install.sh" --target="$PLATFORM_HOME"
  local install_rc=$?
  set -e

  if [[ "$install_rc" -ne 0 ]]; then
    warn "Candidate installer thất bại. Đang rollback transaction..."
    if ! platform_tx_rollback; then
      warn "Package rollback không hoàn tất: $(platform_tx_rollback_failures) callback thất bại."
    fi
    package_tx_history "$tx_history" "$id" "$old_version" "$new_version" "failed-install"
    die "Upgrade thất bại; đã rollback về $old_version."
  fi

  set +e
  "$root/verify.sh" --target="$PLATFORM_HOME"
  local verify_rc=$?
  set -e

  if [[ "$verify_rc" -ne 0 ]]; then
    warn "Candidate verify thất bại. Đang rollback transaction..."
    if ! platform_tx_rollback; then
      warn "Package rollback không hoàn tất: $(platform_tx_rollback_failures) callback thất bại."
    fi
    package_tx_history "$tx_history" "$id" "$old_version" "$new_version" "failed-verify"
    die "Upgrade verify thất bại; đã rollback về $old_version."
  fi

  package_tx_commit_record "$root/manifest.json" "$record" "$old_version" "$tx_root"
  package_tx_history "$tx_history" "$id" "$old_version" "$new_version" "success"
  platform_tx_commit || die "Không thể commit package transaction."
  rm -rf "$tx_root"
  success "Đã nâng $id: $old_version -> $new_version"
}

package_tx_restore_files() {
  local payload="$1" backup="$2"

  while IFS= read -r -d '' src; do
    local rel dst bak
    rel="${src#$payload/}"
    dst="$PLATFORM_HOME/$rel"
    bak="$backup/$rel"

    if [[ -f "$bak" ]]; then
      mkdir -p "$(dirname "$dst")"
      cp -a "$bak" "$dst"
    else
      rm -f "$dst"
    fi
  done < <(find "$payload" -type f -print0)
}

package_tx_restore_record() {
  local old_record="$1" record="$2"
  cp -a "$old_record" "$record"
}

package_tx_cleanup_root() {
  local tx_root="$1"
  rm -rf "$tx_root"
}

package_tx_commit_record() {
  local manifest="$1" record="$2" old_version="$3" tx_root="$4"

  python3 - "$manifest" "$record" "$old_version" "$tx_root" <<'PY'
import json,sys,datetime,os
manifest_path,record_path,old_version,tx_root=sys.argv[1:]
with open(manifest_path,encoding="utf-8") as f:m=json.load(f)

candidate={}
if os.path.isfile(record_path):
    try:
        with open(record_path,encoding="utf-8") as f:candidate=json.load(f)
    except Exception:
        candidate={}

out={
    "id":m["id"],
    "name":m["name"],
    "version":m["version"],
    "type":m["type"],
    "installed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "upgraded_from":old_version,
}
for key in ("backup_dir","installed_files","new_files"):
    if key in candidate:
        out[key]=candidate[key]

tmp=record_path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(out,f,ensure_ascii=False,indent=2);f.write("\n")
os.replace(tmp,record_path)
PY
}

package_tx_history() {
  local history="$1" id="$2" old="$3" new="$4" status="$5"

  python3 - "$history" "$id" "$old" "$new" "$status" <<'PY'
import json,sys,datetime
path,id_,old,new,status=sys.argv[1:]
row={
 "at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "id":id_,
 "action":"upgrade",
 "from_version":old,
 "version":new,
 "status":status,
}
with open(path,"a",encoding="utf-8") as f:
    f.write(json.dumps(row,ensure_ascii=False)+"\n")
PY
}

package_list() {
  package_init_state
  local found=0 file
  shopt -s nullglob
  for file in "$(package_installed_dir)"/*.json; do
    found=1
    python3 - "$file" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
print(f"{d.get('id','-'):12} {d.get('version','-'):18} {d.get('name','-')}")
PY
  done
  [[ "$found" -eq 1 ]] || echo "Chưa có package."
}

package_show() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "USAGE: platform package show <id>"
  local r
  r="$(package_record_path "$id")"
  [[ -f "$r" ]] || die "Package chưa cài: $id"
  python3 -m json.tool "$r"
}

package_verify() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "USAGE: platform package verify <id>"
  local r
  r="$(package_record_path "$id")"
  [[ -f "$r" ]] || die "Package record không tồn tại: $id"

  python3 - "$r" "$PLATFORM_HOME" <<'PY'
import json,sys,os
with open(sys.argv[1],encoding="utf-8") as f:r=json.load(f)
for rel in r.get("installed_files",[]):
    if not os.path.isfile(os.path.join(sys.argv[2],rel)):
        raise SystemExit("missing: "+rel)
PY
  success "$id hợp lệ."
}

package_history() {
  local id="${1:-}"
  [[ -n "$id" ]] || die "USAGE: platform package history <id>"
  local f
  f="$(package_history_dir)/${id}.jsonl"
  [[ -f "$f" ]] && cat "$f" || echo "Chưa có history."
}
