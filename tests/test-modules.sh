#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for module in "$ROOT"/modules/*; do
  [[ -d "$module" ]] || continue
  [[ -x "$module/commands/help.sh" ]] || {
    echo "[ERROR] Missing help.sh: $module"
    exit 1
  }
done

echo "[OK] module tests"
