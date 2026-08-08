#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE="${1:-/opt/laravel-deployment-platform}"
TARGET="${2:-/opt/laravel-deployment-platform-v2}"
DRY_RUN="${DRY_RUN:-1}"

copy_file() {
  local src="$1" dst="$2"
  [[ -f "$src" ]] || return 0
  if [[ "$DRY_RUN" == "1" ]]; then
    echo "[DRY-RUN] $src -> $dst"
  else
    mkdir -p "$(dirname "$dst")"
    cp -a "$src" "$dst"
  fi
}

copy_file "$SOURCE/commands/site/list.sh"      "$TARGET/modules/site/commands/list.sh"
copy_file "$SOURCE/commands/site/show.sh"      "$TARGET/modules/site/commands/show.sh"
copy_file "$SOURCE/commands/site/create.sh"    "$TARGET/modules/site/commands/create.sh"
copy_file "$SOURCE/commands/site/duplicate.sh" "$TARGET/modules/site/commands/duplicate.sh"
copy_file "$SOURCE/commands/site/rename.sh"    "$TARGET/modules/site/commands/rename.sh"
copy_file "$SOURCE/commands/site/remove.sh"    "$TARGET/modules/site/commands/remove.sh"
copy_file "$SOURCE/commands/site/exec.sh"      "$TARGET/modules/site/commands/exec.sh"
copy_file "$SOURCE/commands/site/doctor.sh"    "$TARGET/modules/site/commands/doctor.sh"

copy_file "$SOURCE/commands/db.sh"             "$TARGET/modules/database/commands/legacy.sh"
copy_file "$SOURCE/commands/build.sh"          "$TARGET/modules/deploy/commands/legacy-build.sh"
copy_file "$SOURCE/commands/doctor.sh"         "$TARGET/modules/doctor/commands/legacy.sh"
copy_file "$SOURCE/lib/inventory.sh"           "$TARGET/modules/inventory/lib/inventory-v1.sh"
copy_file "$SOURCE/lib/render-nginx.sh"        "$TARGET/modules/site/lib/render-nginx-v1.sh"

echo "[OK] Migration layout plan completed. DRY_RUN=$DRY_RUN"
