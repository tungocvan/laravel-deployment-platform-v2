#!/usr/bin/env bash

inventory_file() {
  printf '%s' "${INVENTORY_FILE:-$PLATFORM_HOME/state/sites.json}"
}

inventory_init() {
  local file
  file="$(inventory_file)"
  mkdir -p "$(dirname "$file")"

  if [[ ! -f "$file" ]]; then
    printf '{"schema_version":2,"sites":[],"reserved_resources":[]}\n' > "$file"
  fi

  python3 - "$file" <<'PY'
import json,sys,os
p=sys.argv[1]
with open(p,encoding="utf-8") as f:d=json.load(f)
changed=False
if "schema_version" not in d:
    d["schema_version"]=2; changed=True
if "sites" not in d:
    d["sites"]=[]; changed=True
if "reserved_resources" not in d:
    d["reserved_resources"]=[]; changed=True
if changed:
    tmp=p+".tmp"
    with open(tmp,"w",encoding="utf-8") as f:
        json.dump(d,f,ensure_ascii=False,indent=2); f.write("\n")
    os.replace(tmp,p)
PY
}

inventory_read_env() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 1
  sed -n -E "s/^${key}=(.*)$/\1/p" "$file" \
    | tail -n1 \
    | sed -E 's/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/'
}

inventory_find_json() {
  local key="$1"
  inventory_init
  python3 - "$(inventory_file)" "$key" <<'PY'
import json,sys
path,key=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
for s in d.get("sites",[]):
    if key in (str(s.get("name","")),str(s.get("domain","")),str(s.get("path",""))):
        print(json.dumps(s,ensure_ascii=False)); raise SystemExit(0)
raise SystemExit(1)
PY
}

inventory_get_field() {
  local key="$1" field="$2"
  inventory_find_json "$key" \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get(sys.argv[1],""); print("" if v is None else v)' "$field"
}

inventory_runtime_compose_config() {
  local project_dir="$1"
  local compose="/opt/laravel-docker-platform/scripts/compose.sh"
  [[ -n "${DOCKER_PLATFORM_DIR:-}" ]] && compose="$DOCKER_PLATFORM_DIR/scripts/compose.sh"
  [[ -x "$compose" ]] || return 1
  PROJECT_DIR="$project_dir" "$compose" config 2>/dev/null
}

inventory_compose_published_port() {
  local config="$1" service="$2"
  python3 - "$service" "$config" <<'PY'
import re,sys
service,text=sys.argv[1:]
inside=False
for line in text.splitlines():
    if line == f"  {service}:":
        inside=True; continue
    if inside and line and not line.startswith("    "):
        break
    if inside and "published:" in line:
        m=re.search(r'published:\s*"?([0-9]+)"?',line)
        if m:
            print(m.group(1)); raise SystemExit(0)
raise SystemExit(1)
PY
}

inventory_runtime_status() {
  local project_dir="$1"
  local compose="/opt/laravel-docker-platform/scripts/compose.sh"
  [[ -n "${DOCKER_PLATFORM_DIR:-}" ]] && compose="$DOCKER_PLATFORM_DIR/scripts/compose.sh"
  [[ -x "$compose" ]] || { echo "unknown"; return 0; }

  local output
  output="$(PROJECT_DIR="$project_dir" "$compose" ps -a web 2>/dev/null || true)"
  if grep -Eq 'Up|healthy|health: starting' <<<"$output"; then
    echo "active"
  elif grep -Eq 'Exited|unhealthy|Restarting' <<<"$output"; then
    echo "error"
  else
    echo "inactive"
  fi
}

inventory_discover_runtime_json() {
  local project_dir="$1" requested_name="${2:-}"
  [[ -d "$project_dir" ]] || die "Project path không tồn tại: $project_dir"

  local app_url domain database http_port socket_port repo branch commit status config
  app_url="$(inventory_read_env "$project_dir/.env" APP_URL 2>/dev/null || true)"
  database="$(inventory_read_env "$project_dir/.env" DB_DATABASE 2>/dev/null || true)"
  http_port="$(inventory_read_env "$project_dir/.docker-platform.env" HTTP_PORT 2>/dev/null || true)"
  socket_port="$(inventory_read_env "$project_dir/.docker-platform.env" SOCKET_PORT 2>/dev/null || true)"

  domain="${app_url#http://}"; domain="${domain#https://}"; domain="${domain%%/*}"
  repo=""; branch=""; commit=""

  if [[ -d "$project_dir/.git" ]]; then
    repo="$(git -C "$project_dir" remote get-url origin 2>/dev/null || true)"
    branch="$(git -C "$project_dir" branch --show-current 2>/dev/null || true)"
    commit="$(git -C "$project_dir" rev-parse HEAD 2>/dev/null || true)"
  fi

  config="$(inventory_runtime_compose_config "$project_dir" 2>/dev/null || true)"
  if [[ -n "$config" ]]; then
    local compose_http compose_socket
    compose_http="$(inventory_compose_published_port "$config" web 2>/dev/null || true)"
    compose_socket="$(inventory_compose_published_port "$config" socket 2>/dev/null || true)"
    [[ -n "$compose_http" ]] && http_port="$compose_http"
    [[ -n "$compose_socket" ]] && socket_port="$compose_socket"
  fi

  status="$(inventory_runtime_status "$project_dir")"

  python3 - "$requested_name" "$domain" "$project_dir" "$http_port" "$socket_port" \
    "$database" "$repo" "$branch" "$commit" "$status" <<'PY'
import json,sys
name,domain,path,http,socket,database,repo,branch,commit,status=sys.argv[1:]
def n(v):
    try:return int(v) if v else None
    except:return None
print(json.dumps({
"name":name or None,"domain":domain or None,"path":path,
"http_port":n(http),"socket_port":n(socket),
"database":database or None,"repo":repo or None,"branch":branch or None,
"commit":commit or None,"status":status
},ensure_ascii=False))
PY
}

inventory_upsert_json() {
  local key="$1" runtime_json="$2"
  inventory_init
  python3 - "$(inventory_file)" "$key" "$runtime_json" <<'PY'
import json,sys,os,datetime
path,key,raw=sys.argv[1:]
runtime=json.loads(raw)
with open(path,encoding="utf-8") as f:d=json.load(f)
d.setdefault("schema_version",2); d.setdefault("sites",[]); d.setdefault("reserved_resources",[])
site=None
for item in d["sites"]:
    if key in (str(item.get("name","")),str(item.get("domain","")),str(item.get("path",""))):
        site=item; break
if site is None:
    site={}; d["sites"].append(site)
for k,v in runtime.items():
    if v not in (None,""): site[k]=v
site["type"]="laravel"
site["managed"]=True
site["last_synced_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2); f.write("\n")
os.replace(tmp,path)
PY
}

inventory_list() {
  inventory_init
  python3 - "$(inventory_file)" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
sites=d.get("sites",[])
if not sites:
    print("Chưa có Laravel site trong inventory."); raise SystemExit
headers=("NAME","DOMAIN","HTTP","SOCKET","DB","PATH","STATUS")
rows=[(
 str(s.get("name","-")),str(s.get("domain","-")),str(s.get("http_port","-")),
 str(s.get("socket_port","-") if s.get("socket_port") is not None else "-"),
 str(s.get("database","-")),str(s.get("path","-")),str(s.get("status","-"))
) for s in sites]
w=[len(x) for x in headers]
for r in rows:
    for i,v in enumerate(r):w[i]=max(w[i],len(v))
fmt=lambda r:"  ".join(v.ljust(w[i]) for i,v in enumerate(r))
print(fmt(headers));print(fmt(tuple("-"*x for x in w)))
for r in rows:print(fmt(r))
PY
}

inventory_show() {
  local key="${1:-}"
  [[ -n "$key" ]] || die "USAGE: platform inventory show <name|domain|path>"
  inventory_find_json "$key" | python3 -m json.tool
}

inventory_reserved() {
  inventory_init
  python3 - "$(inventory_file)" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
rows=d.get("reserved_resources",[])
if not rows:
    print("Chưa có reserved resource."); raise SystemExit
headers=("NAME","APP","DOMAIN","HTTP","PATH","MANAGED")
data=[(
 str(x.get("name","-")),str(x.get("application","-")),str(x.get("domain","-")),
 str(x.get("http_port","-")),str(x.get("path","-")),str(x.get("managed",False))
) for x in rows]
w=[len(x) for x in headers]
for r in data:
    for i,v in enumerate(r):w[i]=max(w[i],len(v))
fmt=lambda r:"  ".join(v.ljust(w[i]) for i,v in enumerate(r))
print(fmt(headers));print(fmt(tuple("-"*x for x in w)))
for r in data:print(fmt(r))
PY
}

inventory_reserve() {
  local name="" application="external" domain="" http_port="" path="" note=""
  for arg in "$@"; do
    case "$arg" in
      --name=*) name="${arg#*=}" ;;
      --application=*) application="${arg#*=}" ;;
      --domain=*) domain="${arg#*=}" ;;
      --http-port=*) http_port="${arg#*=}" ;;
      --path=*) path="${arg#*=}" ;;
      --note=*) note="${arg#*=}" ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  [[ -n "$name" ]] || die "Thiếu --name"
  [[ "$http_port" =~ ^[0-9]+$ ]] || die "--http-port phải là số"
  ((http_port >= 1 && http_port <= 65535)) || die "Port không hợp lệ"

  inventory_init

  python3 - "$(inventory_file)" "$name" "$application" "$domain" "$http_port" "$path" "$note" <<'PY'
import json,sys,os,datetime
file,name,app,domain,http,path,note=sys.argv[1:]
http=int(http)
with open(file,encoding="utf-8") as f:d=json.load(f)
d.setdefault("sites",[]); d.setdefault("reserved_resources",[])

# Không cho reserve port đang thuộc Laravel site khác.
for s in d["sites"]:
    if s.get("name") != name and s.get("http_port") == http:
        raise SystemExit(f"HTTP port {http} đang thuộc Laravel site {s.get('name')}")

# Remove same-name accidental site entry.
d["sites"]=[s for s in d["sites"] if s.get("name") != name]

# Upsert reserved resource by name.
entry=None
for r in d["reserved_resources"]:
    if r.get("name")==name:
        entry=r; break
if entry is None:
    entry={}; d["reserved_resources"].append(entry)

entry.update({
    "name":name,
    "type":"external",
    "application":app or "external",
    "http_port":http,
    "managed":False,
    "reserved_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
})
if domain: entry["domain"]=domain
if path: entry["path"]=path
if note: entry["note"]=note

# Duplicate reserved port check.
owners=[r.get("name") for r in d["reserved_resources"] if r.get("http_port")==http]
if len(owners)>1:
    raise SystemExit(f"HTTP port {http} bị reserve trùng: {', '.join(owners)}")

tmp=file+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n")
os.replace(tmp,file)
PY

  success "Đã reserve HTTP port $http_port cho $name"
}

inventory_unreserve() {
  local name="${1:-}"
  [[ -n "$name" ]] || die "USAGE: platform inventory unreserve <name>"
  inventory_init
  python3 - "$(inventory_file)" "$name" <<'PY'
import json,sys,os
file,name=sys.argv[1:]
with open(file,encoding="utf-8") as f:d=json.load(f)
before=len(d.get("reserved_resources",[]))
d["reserved_resources"]=[r for r in d.get("reserved_resources",[]) if r.get("name")!=name]
if len(d["reserved_resources"])==before:
    raise SystemExit("reserved resource not found")
tmp=file+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n")
os.replace(tmp,file)
PY
  success "Đã unreserve: $name"
}

inventory_port_used() {
  local port="$1"
  inventory_init

  python3 - "$(inventory_file)" "$port" <<'PY' && return 0 || true
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
p=int(sys.argv[2])
for s in d.get("sites",[]):
    if s.get("http_port")==p or s.get("socket_port")==p: raise SystemExit(0)
for r in d.get("reserved_resources",[]):
    if r.get("http_port")==p or r.get("socket_port")==p: raise SystemExit(0)
raise SystemExit(1)
PY

  ss -lntH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$" && return 0
  docker ps --format '{{.Ports}}' 2>/dev/null | grep -Eq "(^|[^0-9])${port}->" && return 0
  return 1
}

inventory_find_free_port() {
  local port="$1"
  while inventory_port_used "$port"; do
    port=$((port+1))
    ((port<=65535)) || die "Không còn port hợp lệ"
  done
  echo "$port"
}

inventory_validate() {
  inventory_init
  python3 - "$(inventory_file)" <<'PY'
import json,sys,os,collections
path=sys.argv[1]
try:
    with open(path,encoding="utf-8") as f:d=json.load(f)
except Exception as e:
    print(f"[ERROR] JSON invalid: {e}"); raise SystemExit(1)

errors=[]
if not isinstance(d,dict):
    errors.append("root phải là object")
else:
    sites=d.get("sites")
    reserved=d.get("reserved_resources")
    if not isinstance(sites,list): errors.append("sites phải là array")
    if not isinstance(reserved,list): errors.append("reserved_resources phải là array")

    if isinstance(sites,list):
        required=("name","domain","path","http_port","database","repo","branch","status")
        for i,s in enumerate(sites):
            if not isinstance(s,dict):
                errors.append(f"sites[{i}] không phải object"); continue
            for field in required:
                if s.get(field) in (None,""):
                    errors.append(f"{s.get('name',i)} thiếu {field}")
            if s.get("path") and not os.path.isdir(s["path"]):
                errors.append(f"{s.get('name',i)} path không tồn tại: {s['path']}")

    if isinstance(reserved,list):
        for i,r in enumerate(reserved):
            if not isinstance(r,dict):
                errors.append(f"reserved_resources[{i}] không phải object"); continue
            for field in ("name","http_port"):
                if r.get(field) in (None,""):
                    errors.append(f"reserved[{i}] thiếu {field}")

    # duplicate names across both groups
    names=collections.defaultdict(list)
    for s in sites if isinstance(sites,list) else []:
        if s.get("name"): names[s["name"]].append("site")
    for r in reserved if isinstance(reserved,list) else []:
        if r.get("name"): names[r["name"]].append("reserved")
    for n,kinds in names.items():
        if len(kinds)>1: errors.append(f"name trùng giữa inventory groups: {n}")

    # all ports must be unique
    ports=collections.defaultdict(list)
    for s in sites if isinstance(sites,list) else []:
        for f in ("http_port","socket_port"):
            if s.get(f) is not None: ports[str(s[f])].append(f"site:{s.get('name')}:{f}")
    for r in reserved if isinstance(reserved,list) else []:
        for f in ("http_port","socket_port"):
            if r.get(f) is not None: ports[str(r[f])].append(f"reserved:{r.get('name')}:{f}")
    for p,owners in ports.items():
        if len(owners)>1: errors.append(f"port {p} trùng: {', '.join(owners)}")

if errors:
    for e in errors: print(f"[ERROR] {e}")
    raise SystemExit(1)
print("[OK] Inventory hợp lệ.")
PY
}

inventory_sync() {
  require_command python3
  require_command git
  local key="${1:-}"; shift || true
  local explicit_path="" explicit_name=""
  for arg in "$@"; do
    case "$arg" in
      --path=*) explicit_path="${arg#*=}" ;;
      --name=*) explicit_name="${arg#*=}" ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done
  [[ -n "$key" ]] || die "USAGE: platform inventory sync <site|path> [--path=...] [--name=...]"

  local project_dir="$explicit_path" name="$explicit_name"
  if inventory_find_json "$key" >/dev/null 2>&1; then
    [[ -n "$project_dir" ]] || project_dir="$(inventory_get_field "$key" path)"
    [[ -n "$name" ]] || name="$(inventory_get_field "$key" name)"
  elif [[ -d "$key" ]]; then
    [[ -n "$project_dir" ]] || project_dir="$key"
  fi

  [[ -n "$project_dir" ]] || die "Site chưa có trong inventory. Cần --path=/opt/project."
  [[ -n "$name" ]] || die "Site chưa có trong inventory. Cần --name=<name>."

  local runtime_json
  runtime_json="$(inventory_discover_runtime_json "$project_dir" "$name")"
  inventory_upsert_json "$key" "$runtime_json"

  if ! inventory_validate; then
    die "Sync đã ghi runtime metadata nhưng inventory chưa hợp lệ."
  fi

  success "Đã sync inventory: $name"
  inventory_show "$name"
}

inventory_repair() {
  local key="${1:-}"
  [[ -n "$key" ]] || die "USAGE: platform inventory repair <site>"
  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy Laravel site: $key"
  warn "Repair dev.2 chỉ re-sync metadata; không tự thay port."
  inventory_sync "$key"
}
