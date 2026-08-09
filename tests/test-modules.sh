#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for module in "$ROOT"/modules/*; do
  [[ -d "$module" ]] || continue

  # Library-only/internal modules (for example lifecycle) are valid and do not
  # expose CLI commands. Only dispatchable modules with commands/ must provide
  # an executable help command.
  [[ -d "$module/commands" ]] || continue

  [[ -x "$module/commands/help.sh" ]] || {
    echo "[ERROR] Missing help.sh: $module"
    exit 1
  }
done

echo "[OK] module tests"
