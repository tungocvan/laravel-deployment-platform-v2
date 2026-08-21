#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/check-system.sh"

fail() {
  echo "[ERROR] $*"
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if grep -Fq -- "$needle" <<<"$haystack"; then
    echo "[OK] $label"
  else
    echo "[ERROR] Missing help contract: $label"
    echo "[ERROR] Expected literal: $needle"
    return 1
  fi
}

[[ -f "$SCRIPT" ]] || fail "Missing check-system.sh"
[[ -x "$SCRIPT" ]] || fail "check-system.sh must be executable"

bash -n "$SCRIPT" || fail "check-system.sh syntax invalid"
echo '[OK] check-system.sh syntax'

set +e
HELP_OUTPUT="$("$SCRIPT" --help 2>&1)"
HELP_EXIT=$?
set -e
[[ "$HELP_EXIT" -eq 0 ]] || {
  echo "$HELP_OUTPUT"
  fail "--help must exit 0, got $HELP_EXIT"
}

assert_contains "$HELP_OUTPUT" 'Laravel Deployment Platform v2 — check-system.sh' 'help title'
assert_contains "$HELP_OUTPUT" 'HỆ ĐIỀU HÀNH KHUYẾN NGHỊ' 'recommended OS section'
assert_contains "$HELP_OUTPUT" 'Ubuntu Server 24.04 LTS' 'Ubuntu 24.04 baseline'
assert_contains "$HELP_OUTPUT" 'CÀI DOCKER CE TỪ OFFICIAL APT REPOSITORY' 'Docker CE install section'
assert_contains "$HELP_OUTPUT" 'Host VPS KHÔNG cần cài PHP,' 'host/runtime separation'
assert_contains "$HELP_OUTPUT" 'platform-v2 0   # SAI' 'invalid direct menu-zero guidance'
assert_contains "$HELP_OUTPUT" 'INFORMATION.md' 'project handoff document'
assert_contains "$HELP_OUTPUT" 'docs/VPS-DEPLOYMENT-GUIDE.md' 'VPS deployment guide'

INVALID_OUT="$(mktemp /tmp/platform-check-system-invalid.XXXXXX)"
trap 'rm -f "$INVALID_OUT"' EXIT

set +e
"$SCRIPT" --invalid-option >"$INVALID_OUT" 2>&1
INVALID_EXIT=$?
set -e
[[ "$INVALID_EXIT" -eq 2 ]] || {
  cat "$INVALID_OUT"
  fail "invalid option must exit 2, got $INVALID_EXIT"
}

grep -Fq '[ERROR] Tham số không hợp lệ' "$INVALID_OUT" || {
  cat "$INVALID_OUT"
  fail 'invalid option must print Vietnamese error'
}
echo '[OK] invalid option contract'

# install.sh must support the common production layout where the repository is
# cloned directly into PLATFORM_INSTALL_DIR. This is a static contract check so
# the test never writes /usr/local/bin or production state.
INSTALL_SCRIPT="$ROOT/install.sh"
[[ -f "$INSTALL_SCRIPT" ]] || fail 'Missing install.sh'
bash -n "$INSTALL_SCRIPT" || fail 'install.sh syntax invalid'
grep -Fq 'Source đã nằm đúng thư mục cài đặt' "$INSTALL_SCRIPT" || \
  fail 'install.sh must guard SRC == DST instead of cp onto itself'
echo '[OK] install.sh same-directory guard contract'

echo '[OK] check-system.sh help/readiness contract'
