#!/usr/bin/env bash
set -Eeuo pipefail

export PLATFORM_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$PLATFORM_HOME/bin/platform" version >/dev/null
"$PLATFORM_HOME/bin/platform" modules | grep -qx site
"$PLATFORM_HOME/bin/platform" modules | grep -qx deploy

echo "[OK] core tests"
