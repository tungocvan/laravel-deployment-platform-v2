#!/usr/bin/env bash

platform_audit_root() {
  printf '%s' "${PLATFORM_AUDIT_ROOT:-$PLATFORM_HOME/state/audit}"
}

platform_audit_now() {
  if [[ -n "${PLATFORM_AUDIT_NOW:-}" ]]; then
    printf '%s' "$PLATFORM_AUDIT_NOW"
  else
    date -u +%Y-%m-%dT%H:%M:%SZ
  fi
}

platform_audit_actor() {
  if [[ -n "${PLATFORM_AUDIT_ACTOR:-}" ]]; then
    printf '%s' "$PLATFORM_AUDIT_ACTOR"
  elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    printf '%s' "$SUDO_USER"
  elif [[ -n "${USER:-}" ]]; then
    printf '%s' "$USER"
  else
    id -un
  fi
}

platform_audit_write() {
  local module="${1:-}" command="${2:-}" target="${3:-}" result="${4:-}"
  local error_code="${5:-}" transaction_id="${6:-}" rollback_status="${7:-not-required}"

  [[ -n "$module" && -n "$command" && -n "$result" ]] || return 1

  case "$result" in
    success|failed|rollback-partial|rollback-failed) ;;
    *) return 1 ;;
  esac

  case "$rollback_status" in
    not-required|not-attempted|success|partial|failed) ;;
    *) return 1 ;;
  esac

  local root at actor month file
  root="$(platform_audit_root)"
  at="$(platform_audit_now)"
  actor="$(platform_audit_actor)"
  month="${at:0:7}"
  [[ "$month" =~ ^[0-9]{4}-[0-9]{2}$ ]] || return 1

  mkdir -p "$root" || return 1
  chmod 700 "$root" 2>/dev/null || true
  file="$root/events-$month.jsonl"

  python3 - "$file" "$at" "$actor" "$module" "$command" "$target" "$result" "$error_code" "$transaction_id" "$rollback_status" <<'PY'
import json, os, sys
path, at, actor, module, command, target, result, error_code, transaction_id, rollback_status = sys.argv[1:]
row = {
    "schema_version": 1,
    "at": at,
    "actor": actor,
    "module": module,
    "command": command,
    "target": target or None,
    "result": result,
    "error_code": error_code or None,
    "transaction_id": transaction_id or None,
    "rollback_status": rollback_status,
}
line = json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n"
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
try:
    os.write(fd, line.encode("utf-8"))
    os.fsync(fd)
finally:
    os.close(fd)
os.chmod(path, 0o600)
PY
}
