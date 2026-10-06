#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
OPS="$ROOT/modules/site/lib/operations.sh"
UI="$ROOT/modules/ui/menus/site-operations-v2.sh"
HELP="$ROOT/modules/site/commands/help.sh"
LEGACY="$ROOT/modules/ui/menus/sites.sh"

grep -q 'script="$path/production-cleanup.sh"' "$OPS"
grep -q '"$script" --report' "$OPS"
grep -q '"$script" "$mode"' "$OPS"
grep -q -- '--apply) mode="--logs"' "$OPS"
grep -q -- '--docker) mode="--docker"' "$OPS"
grep -q -- '--all) mode="--all"' "$OPS"
grep -q 'Docker cleanup is HOST-WIDE' "$OPS"
grep -q 'php artisan optimize:clear' "$OPS"

grep -q '7) Production Cleanup — report-only mặc định' "$UI"
grep -q '7) ui_flow_production_cleanup ;;' "$UI"
grep -q 'ui_flow_production_cleanup()' "$UI"
grep -q 'HOST-WIDE DOCKER CLEANUP' "$UI"
grep -q 'site cleanup "$site" --apply --yes' "$UI"
grep -q 'site cleanup "$site" --docker --yes' "$UI"
grep -q 'site cleanup "$site" --all --yes' "$UI"

grep -q 'cleanup <site> \[--apply|--docker|--all\] \[--yes\]' "$HELP"
! grep -q '19) Production Cleanup' "$LEGACY"
! grep -q 'ui_flow_production_cleanup()' "$LEGACY"

echo "[PASS] Production cleanup contract regression checks passed."
