#!/usr/bin/env bash
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="${PLATFORM_INSTALL_DIR:-/opt/laravel-deployment-platform-v2}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
  echo "[ERROR] Hãy chạy bằng sudo/root."
  exit 1
}

SRC_REAL="$(readlink -f "$SRC")"
mkdir -p "$DST"
DST_REAL="$(readlink -f "$DST")"

if [[ "$SRC_REAL" == "$DST_REAL" ]]; then
  echo "[INFO] Source đã nằm đúng thư mục cài đặt: $DST_REAL"
  echo "[INFO] Bỏ qua bước copy; chỉ chuẩn hóa runtime files và CLI symlink."
else
  echo "[INFO] Install source: $SRC_REAL"
  echo "[INFO] Install target: $DST_REAL"
  cp -a "$SRC_REAL/." "$DST_REAL/"
fi

mkdir -p "$DST_REAL/state"
[[ -f "$DST_REAL/state/sites.json" ]] || printf '{"schema_version":2,"sites":[]}\n' > "$DST_REAL/state/sites.json"

find "$DST_REAL" -type f -name '*.sh' -exec chmod 0755 {} \;
chmod 0755 "$DST_REAL/bin/platform"

ln -sfn "$DST_REAL/bin/platform" /usr/local/bin/platform-v2

echo "[OK] Platform CLI đã sẵn sàng: /usr/local/bin/platform-v2"
echo "[OK] PLATFORM_HOME: $DST_REAL"
echo "Run: platform-v2"
echo "Check system: $DST_REAL/check-system.sh"
