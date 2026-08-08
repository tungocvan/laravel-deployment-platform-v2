#!/usr/bin/env bash
set -Eeuo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="${PLATFORM_INSTALL_DIR:-/opt/laravel-deployment-platform-v2}"

[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
  echo "[ERROR] Hãy chạy bằng sudo/root."
  exit 1
}

mkdir -p "$DST"
cp -a "$SRC/." "$DST/"

mkdir -p "$DST/state"
[[ -f "$DST/state/sites.json" ]] || printf '{"schema_version":2,"sites":[]}\n' > "$DST/state/sites.json"

find "$DST" -type f -name '*.sh' -exec chmod 0755 {} \;
chmod 0755 "$DST/bin/platform"

ln -sfn "$DST/bin/platform" /usr/local/bin/platform-v2

echo "[OK] Installed staging CLI: platform-v2"
echo "Run: platform-v2 --help"
