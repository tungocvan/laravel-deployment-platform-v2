#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/check-system.sh"

[[ -f "$SCRIPT" ]] || { echo "[ERROR] Missing check-system.sh"; exit 1; }
[[ -x "$SCRIPT" ]] || { echo "[ERROR] check-system.sh must be executable"; exit 1; }

bash -n "$SCRIPT"

HELP_OUTPUT="$("$SCRIPT" --help)"
grep -Fq 'Laravel Deployment Platform v2 — check-system.sh' <<<"$HELP_OUTPUT"
grep -Fq 'HỆ ĐIỀU HÀNH KHUYẾN NGHỊ' <<<"$HELP_OUTPUT"
grep -Fq 'Ubuntu Server 24.04 LTS' <<<"$HELP_OUTPUT"
grep -Fq 'CÀI DOCKER CE TỪ OFFICIAL APT REPOSITORY' <<<"$HELP_OUTPUT"
grep -Fq 'HOST VPS KHÔNG cần cài PHP' <<<"$HELP_OUTPUT"
grep -Fq 'platform-v2 0   # SAI' <<<"$HELP_OUTPUT"
grep -Fq 'INFORMATION.md' <<<"$HELP_OUTPUT"
grep -Fq 'docs/VPS-DEPLOYMENT-GUIDE.md' <<<"$HELP_OUTPUT"

set +e
"$SCRIPT" --invalid-option >/tmp/platform-check-system-invalid.out 2>&1
INVALID_EXIT=$?
set -e
[[ "$INVALID_EXIT" -eq 2 ]] || {
  echo "[ERROR] invalid option must exit 2, got $INVALID_EXIT"
  cat /tmp/platform-check-system-invalid.out
  exit 1
}

grep -Fq '[ERROR] Tham số không hợp lệ' /tmp/platform-check-system-invalid.out
rm -f /tmp/platform-check-system-invalid.out

echo '[OK] check-system.sh help/readiness contract'
