#!/usr/bin/env bash

site_lifecycle_state_root() {
  printf '%s' "$PLATFORM_HOME/state/site-lifecycle"
}

site_lifecycle_state_file() {
  local site="$1"
  printf '%s/%s.json' "$(site_lifecycle_state_root)" "$(site_slugify "$site")"
}

site_archive_root() {
  printf '%s' "$PLATFORM_HOME/state/site-lifecycle/archived"
}

site_archive_file() {
  local site="$1"
  printf '%s/%s.json' "$(site_archive_root)" "$(site_slugify "$site")"
}

site_lifecycle_write_state() {
  local site="$1" state="$2" reason="${3:-}"
  local path domain database http socket file
  path="$(inventory_get_field "$site" path 2>/dev/null || true)"
  domain="$(inventory_get_field "$site" domain 2>/dev/null || true)"
  database="$(inventory_get_field "$site" database 2>/dev/null || true)"
  http="$(inventory_get_field "$site" http_port 2>/dev/null || true)"
  socket="$(inventory_get_field "$site" socket_port 2>/dev/null || true)"
  file="$(site_lifecycle_state_file "$site")"
  mkdir -p "$(dirname "$file")"

  python3 - "$file" "$site" "$state" "$reason" "$path" "$domain" "$database" "$http" "$socket" <<'PY'
import json,sys,datetime,os,tempfile
file,site,state,reason,path,domain,database,http,socket=sys.argv[1:]
data={
  "schema_version":1,
  "site":site,
  "state":state,
  "reason":reason or None,
  "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
  "path":path or None,
  "domain":domain or None,
  "database":database or None,
  "http_port":int(http) if http.isdigit() else None,
  "socket_port":int(socket) if socket.isdigit() else None
}
os.makedirs(os.path.dirname(file),exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=".lifecycle.",dir=os.path.dirname(file))
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(data,f,ensure_ascii=False,indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp,file)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
}

site_lifecycle_read_state() {
  local site="$1" file
  file="$(site_lifecycle_state_file "$site")"
  if [[ ! -f "$file" ]]; then
    printf 'unknown'
    return 0
  fi
  python3 - "$file" <<'PY'
import json,sys
try:
    with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
    print(d.get("state","unknown"))
except Exception:
    print("unknown")
PY
}

site_lifecycle_resolve() {
  local site="$1"
  inventory_find_json "$site" >/dev/null 2>&1 || die "Site không tồn tại trong Inventory: $site"

  local path domain
  path="$(inventory_get_field "$site" path)"
  domain="$(inventory_get_field "$site" domain)"
  [[ -n "$path" && -d "$path" ]] || die "Path site không tồn tại: $path"
  [[ -n "$domain" ]] || die "Site thiếu domain: $site"
  printf '%s|%s' "$path" "$domain"
}

site_lifecycle_confirm() {
  local prompt="$1" answer
  read -r -p "$prompt [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}

site_disable() {
  require_root
  local site="${1:-}" auto_yes=0 arg
  shift || true
  [[ -n "$site" ]] || die "USAGE: platform site disable <site> [--yes]"
  for arg in "$@"; do
    case "$arg" in --yes) auto_yes=1 ;; *) die "Option không hợp lệ: $arg" ;; esac
  done

  local resolved path domain state
  resolved="$(site_lifecycle_resolve "$site")"
  path="${resolved%%|*}"; domain="${resolved#*|}"
  state="$(site_lifecycle_read_state "$site")"

  if [[ "$state" == "disabled" ]]; then
    success "Site đã disabled: $site"
    return 0
  fi

  [[ "$auto_yes" -eq 1 ]] || site_lifecycle_confirm "Disable site?" || die "Đã hủy."

  local nginx_disabled=0 docker_stopped=0
  trap 'rc=$?
    if [[ $rc -ne 0 ]]; then
      warn "Disable thất bại. Rollback best-effort..."
      [[ $docker_stopped -eq 1 ]] && deploy_compose "$path" up -d >/dev/null 2>&1 || true
      [[ $nginx_disabled -eq 1 ]] && platform_nginx_enable "$domain" >/dev/null 2>&1 || true
    fi
    exit $rc' ERR

  echo "[01/05] Validate runtime"
  deploy_compose "$path" config >/dev/null
  echo "[02/05] Disable Nginx"
  platform_nginx_disable "$domain"; nginx_disabled=1
  echo "[03/05] Stop Docker"
  deploy_compose "$path" stop; docker_stopped=1
  echo "[04/05] Record lifecycle"
  site_lifecycle_write_state "$site" "disabled" "user-request"
  echo "[05/05] Done"

  trap - ERR
  success "Site disabled: $site"
}

site_enable() {
  require_root
  local site="${1:-}" auto_yes=0 arg
  shift || true
  [[ -n "$site" ]] || die "USAGE: platform site enable <site> [--yes]"
  for arg in "$@"; do
    case "$arg" in --yes) auto_yes=1 ;; *) die "Option không hợp lệ: $arg" ;; esac
  done

  local resolved path domain
  resolved="$(site_lifecycle_resolve "$site")"
  path="${resolved%%|*}"; domain="${resolved#*|}"

  [[ "$auto_yes" -eq 1 ]] || site_lifecycle_confirm "Enable site?" || die "Đã hủy."

  echo "[01/06] Validate runtime"
  deploy_compose "$path" config >/dev/null
  echo "[02/06] Start Docker"
  deploy_compose "$path" up -d
  echo "[03/06] Enable Nginx"
  platform_nginx_enable "$domain"
  echo "[04/06] Health"
  site_provision_health "$path"
  echo "[05/06] Inventory sync"
  inventory_sync "$site" --name="$site" --path="$path"
  echo "[06/06] Record lifecycle"
  site_lifecycle_write_state "$site" "active" "user-request"

  success "Site enabled: $site"
}

site_maintenance() {
  require_root
  local action="${1:-}" site="${2:-}"
  [[ -n "$action" && -n "$site" ]] || die "USAGE: platform site maintenance <on|off> <site>"

  local resolved path
  resolved="$(site_lifecycle_resolve "$site")"
  path="${resolved%%|*}"

  case "$action" in
    on)
      [[ "$(site_lifecycle_read_state "$site")" != "disabled" ]] || die "Site đang disabled."
      deploy_compose "$path" exec -T app php artisan down
      site_lifecycle_write_state "$site" "maintenance" "user-request"
      success "Maintenance enabled: $site"
      ;;
    off)
      [[ "$(site_lifecycle_read_state "$site")" != "disabled" ]] || die "Site đang disabled."
      deploy_compose "$path" exec -T app php artisan up
      site_provision_health "$path"
      inventory_sync "$site" --name="$site" --path="$path"
      site_lifecycle_write_state "$site" "active" "user-request"
      success "Maintenance disabled: $site"
      ;;
    *) die "Action maintenance không hợp lệ: $action (on|off)" ;;
  esac
}

site_lifecycle_inventory_remove() {
  local site="$1"
  local inv
  inv="$(inventory_file)"
  inventory_init

  python3 - "$inv" "$site" <<'PY'
import json,sys,os,tempfile
path,site=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
sites=d.get("sites",[])
new=[s for s in sites if s.get("name") != site]
if len(new)==len(sites):
    raise SystemExit("Inventory site not found: "+site)
d["sites"]=new
folder=os.path.dirname(path)
fd,tmp=tempfile.mkstemp(prefix=".sites-archive.",dir=folder)
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
  inventory_validate
}

site_lifecycle_inventory_restore_json() {
  local archived_json="$1"
  local inv
  inv="$(inventory_file)"
  inventory_init

  python3 - "$inv" "$archived_json" <<'PY'
import json,sys,os,tempfile
path,raw=sys.argv[1:]
record=json.loads(raw)
site=record["inventory_record"]
with open(path,encoding="utf-8") as f:d=json.load(f)
sites=d.setdefault("sites",[])
name=site.get("name")
domain=site.get("domain")
pathv=site.get("path")
database=site.get("database")
for s in sites:
    if s.get("name")==name: raise SystemExit("Site name already exists: "+name)
    if domain and s.get("domain")==domain: raise SystemExit("Domain already exists: "+domain)
    if pathv and s.get("path")==pathv: raise SystemExit("Path already exists: "+pathv)
    if database and s.get("database")==database: raise SystemExit("Database already exists: "+database)
sites.append(site)
folder=os.path.dirname(path)
fd,tmp=tempfile.mkstemp(prefix=".sites-unarchive.",dir=folder)
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
  inventory_validate
}

site_archive_write_record() {
  local site="$1" backup_id="$2"
  local inv_json file
  inv_json="$(inventory_find_json "$site")"
  file="$(site_archive_file "$site")"
  mkdir -p "$(dirname "$file")"

  python3 - "$file" "$backup_id" "$inv_json" <<'PY'
import json,sys,datetime,os,tempfile
file,backup,raw=sys.argv[1:]
inv=json.loads(raw)
data={
 "schema_version":1,
 "status":"archived",
 "archived_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "final_backup":backup,
 "inventory_record":inv
}
folder=os.path.dirname(file)
fd,tmp=tempfile.mkstemp(prefix=".archive.",dir=folder)
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(data,f,ensure_ascii=False,indent=2);f.write("\n");f.flush();os.fsync(f.fileno())
    os.replace(tmp,file)
finally:
    if os.path.exists(tmp): os.unlink(tmp)
PY
}

site_archive() {
  require_root
  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform site archive <site> [--dry-run] [--yes]"
  local dry_run=0 auto_yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  local resolved path domain database
  resolved="$(site_lifecycle_resolve "$site")"
  path="${resolved%%|*}"; domain="${resolved#*|}"
  database="$(inventory_get_field "$site" database 2>/dev/null || true)"

  echo "========================================================="
  echo "SITE ARCHIVE PLAN"
  echo "========================================================="
  echo "Site         : $site"
  echo "Domain       : $domain"
  echo "Database     : ${database:-N/A}"
  echo "Path         : $path"
  echo "Final backup : CREATE + VERIFY"
  echo "Docker       : DOWN (volumes preserved)"
  echo "Nginx        : DISABLE (config preserved)"
  echo "Source       : KEEP"
  echo "Volumes/DB   : KEEP"
  echo "SSL          : KEEP"
  echo "Inventory    : REMOVE active record"
  echo "Archive      : KEEP metadata"
  echo "========================================================="

  [[ "$dry_run" -eq 0 ]] || { echo "[DRY-RUN] Không thay đổi hệ thống."; return 0; }
  [[ "$auto_yes" -eq 1 ]] || site_lifecycle_confirm "Archive site?" || die "Đã hủy."

  echo "[ARCHIVE 01/07] Final backup"
  command -v platform_git_verify >/dev/null 2>&1 || die "Git helper chưa được nạp: platform_git_verify"
  command -v backup_create >/dev/null 2>&1 || die "Backup helper chưa được nạp: backup_create"
  command -v backup_verify >/dev/null 2>&1 || die "Backup helper chưa được nạp: backup_verify"
  local backup_id
  backup_id="$(backup_create "$site" | tail -n1)"
  [[ -n "$backup_id" ]] || die "Không lấy được backup id."
  backup_verify "$site" "$backup_id"

  echo "[ARCHIVE 02/07] Save archive metadata"
  site_archive_write_record "$site" "$backup_id"

  echo "[ARCHIVE 03/07] Disable Nginx"
  platform_nginx_disable "$domain" || true

  echo "[ARCHIVE 04/07] Docker down (keep volumes)"
  deploy_compose "$path" down --remove-orphans

  echo "[ARCHIVE 05/07] Inventory detach"
  site_lifecycle_inventory_remove "$site"

  echo "[ARCHIVE 06/07] Lifecycle state"
  mkdir -p "$(site_lifecycle_state_root)"
  python3 - "$(site_lifecycle_state_file "$site")" "$site" "$domain" "$path" "$database" "$backup_id" <<'PY'
import json,sys,datetime
file,site,domain,path,database,backup=sys.argv[1:]
d={"schema_version":1,"site":site,"state":"archived","domain":domain,"path":path,
   "database":database or None,"final_backup":backup,
   "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
with open(file,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n")
PY

  echo "[ARCHIVE 07/07] Verify"
  if inventory_find_json "$site" >/dev/null 2>&1; then
    die "Archive thất bại: site vẫn còn trong active Inventory."
  fi

  success "Site archived: $site"
  echo "Final backup : $site/$backup_id"
  echo "Restore      : sudo platform-v2 site restore-archive $site"
}

site_restore_archive() {
  require_root
  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform site restore-archive <site> [--yes]"
  local auto_yes=0 arg
  for arg in "$@"; do
    case "$arg" in --yes) auto_yes=1 ;; *) die "Option không hợp lệ: $arg" ;; esac
  done

  local file
  file="$(site_archive_file "$site")"
  [[ -f "$file" ]] || die "Không tìm thấy archive record: $site"

  local raw path domain
  raw="$(cat "$file")"
  path="$(python3 - "$file" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
print(d["inventory_record"].get("path",""))
PY
)"
  domain="$(python3 - "$file" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
print(d["inventory_record"].get("domain",""))
PY
)"
  [[ -d "$path" ]] || die "Archived source path không còn tồn tại: $path"

  [[ "$auto_yes" -eq 1 ]] || site_lifecycle_confirm "Restore archived site?" || die "Đã hủy."

  echo "[RESTORE-ARCHIVE 01/06] Restore Inventory"
  site_lifecycle_inventory_restore_json "$raw"

  echo "[RESTORE-ARCHIVE 02/06] Start Docker"
  deploy_compose "$path" up -d

  echo "[RESTORE-ARCHIVE 03/06] Enable Nginx"
  platform_nginx_enable "$domain"

  echo "[RESTORE-ARCHIVE 04/06] Health"
  site_provision_health "$path"

  echo "[RESTORE-ARCHIVE 05/06] Sync Inventory"
  inventory_sync "$site" --name="$site" --path="$path"

  echo "[RESTORE-ARCHIVE 06/06] Lifecycle"
  site_lifecycle_write_state "$site" "active" "restore-archive"

  rm -f "$file"
  success "Archived site restored: $site"
}

site_archives() {
  local root
  root="$(site_archive_root)"
  [[ -d "$root" ]] || { echo "Không có archived site."; return 0; }
  python3 - "$root" <<'PY'
import json,sys,pathlib
root=pathlib.Path(sys.argv[1])
rows=[]
for p in sorted(root.glob("*.json")):
    try:
        d=json.loads(p.read_text(encoding="utf-8"))
        s=d.get("inventory_record",{})
        rows.append((s.get("name",""),s.get("domain",""),s.get("database",""),
                     d.get("final_backup",""),d.get("archived_at","")))
    except Exception:
        pass
if not rows:
    print("Không có archived site.")
else:
    print(f'{"NAME":18} {"DOMAIN":28} {"DATABASE":20} {"BACKUP":18} ARCHIVED_AT')
    for r in rows:
        print(f'{r[0]:18} {r[1]:28} {r[2]:20} {r[3]:18} {r[4]}')
PY
}

site_lifecycle_show() {
  local site="${1:-}"
  [[ -n "$site" ]] || die "USAGE: platform site lifecycle <site>"

  local af
  af="$(site_archive_file "$site")"
  if [[ -f "$af" ]]; then
    echo "Lifecycle : archived"
    cat "$af"
    return 0
  fi

  local resolved path domain file state
  resolved="$(site_lifecycle_resolve "$site")"
  path="${resolved%%|*}"; domain="${resolved#*|}"
  file="$(site_lifecycle_state_file "$site")"
  state="$(site_lifecycle_read_state "$site")"

  echo "Site      : $site"
  echo "Domain    : $domain"
  echo "Path      : $path"
  echo "Lifecycle : $state"
  [[ -f "$file" ]] && { echo; cat "$file"; } || \
    echo "[INFO] Chưa có lifecycle record."
}
