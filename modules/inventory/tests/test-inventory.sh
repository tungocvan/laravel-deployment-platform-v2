#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
for cmd in list show validate sync repair reserve reserved unreserve; do
  [[ -x "$ROOT/modules/inventory/commands/$cmd.sh" ]]
done
grep -q 'inventory_port_used()' "$ROOT/modules/inventory/lib/inventory.sh"
grep -q 'inventory_find_free_port()' "$ROOT/modules/inventory/lib/inventory.sh"
echo "[OK] inventory dev.2 files"
