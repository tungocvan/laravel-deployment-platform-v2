#!/usr/bin/env bash

package_upgrade_audit_failure() {
  local id="$1" error_code="$2" tx_id="$3"
  local failures result rollback_status
  failures="$(platform_tx_rollback_failures)"

  if [[ "$failures" -eq 0 ]]; then
    result="failed"
    rollback_status="success"
  else
    result="rollback-partial"
    rollback_status="partial"
  fi

  platform_audit_try package upgrade "$id" "$result" "$error_code" "$tx_id" "$rollback_status"
}

package_upgrade_audit_success() {
  local id="$1" tx_id="$2"
  platform_audit_try package upgrade "$id" success "" "$tx_id" not-required
}

# Platform 2.1 audited override for package upgrade only.
# package.sh remains the owner of package state/history and rollback callbacks.
package_upgrade() {
  require_root
  require_command unzip
  require_command sha256sum
  require_command python3

  local zip="${1:-}"
  [[ -f "$zip" ]] || die "Không tìm thấy ZIP: $zip"

  package_init_state

  local stage root id new_version target record old_version
  local tx_root tx_backup tx_old_record tx_history tx_id
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

  tx_id="package-upgrade:$id"
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
    rel="${src#"$root"/"$payload_root"/}"
    dst="$PLATFORM_HOME/$rel"
    if [[ -f "$dst" ]]; then
      mkdir -p "$tx_backup/$(dirname "$rel")"
      cp -a "$dst" "$tx_backup/$rel"
    fi
  done < <(find "$root/$payload_root" -type f -print0)

  cp -a "$record" "$tx_root/pre-install-record.json"

  platform_tx_begin "$tx_id" || die "Không thể bắt đầu package transaction."
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
    package_upgrade_audit_failure "$id" PACKAGE.INSTALL_FAILED "$tx_id"
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
    package_upgrade_audit_failure "$id" PACKAGE.VERIFY_FAILED "$tx_id"
    die "Upgrade verify thất bại; đã rollback về $old_version."
  fi

  package_tx_commit_record "$root/manifest.json" "$record" "$old_version" "$tx_root"
  package_tx_history "$tx_history" "$id" "$old_version" "$new_version" "success"
  platform_tx_commit || die "Không thể commit package transaction."
  rm -rf "$tx_root"
  package_upgrade_audit_success "$id" "$tx_id"
  success "Đã nâng $id: $old_version -> $new_version"
}
