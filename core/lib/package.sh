#!/usr/bin/env bash

package_state_root(){ printf '%s/state/packages' "$PLATFORM_HOME"; }
package_installed_dir(){ printf '%s/installed' "$(package_state_root)"; }
package_history_dir(){ printf '%s/history' "$(package_state_root)"; }
package_backup_root(){ printf '%s/state/package-backups' "$PLATFORM_HOME"; }

package_init_state(){
  mkdir -p "$(package_installed_dir)" "$(package_history_dir)" "$(package_backup_root)"
}

package_record_path(){ printf '%s/%s.json' "$(package_installed_dir)" "$1"; }

package_manifest_field(){
  local manifest="$1" field="$2"
  python3 - "$manifest" "$field" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f: d=json.load(f)
v=d
for p in sys.argv[2].split("."):
    v=v.get(p) if isinstance(v,dict) else None
print("" if v is None else v)
PY
}

package_validate_manifest_basic(){
  python3 - "$1" <<'PY'
import json,sys,re
with open(sys.argv[1],encoding="utf-8") as f:m=json.load(f)
req=["schema_version","id","name","version","type","platform","target","payload_root","install"]
missing=[x for x in req if x not in m]
if missing: raise SystemExit("missing fields: "+",".join(missing))
if m["schema_version"]!=2: raise SystemExit("unsupported schema")
if not re.fullmatch(r"Package-\d{3}",str(m["id"])): raise SystemExit("invalid id")
PY
}

package_find_root(){
  local stage="$1"
  local count
  count="$(find "$stage" -mindepth 1 -maxdepth 1 -type d | wc -l)"
  [[ "$count" -eq 1 ]] || die "ZIP phải chứa đúng một root directory."
  find "$stage" -mindepth 1 -maxdepth 1 -type d -print -quit
}
