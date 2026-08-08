#!/usr/bin/env bash

backup_root() {
  printf '%s' "${PLATFORM_BACKUP_ROOT:-/opt/backups/platform-v2}"
}

backup_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g;s/^-+//;s/-+$//'
}

backup_timestamp() { date +%Y%m%d_%H%M%S; }

backup_site_root() {
  printf '%s/%s' "$(backup_root)" "$(backup_slugify "$1")"
}

backup_dir() {
  printf '%s/%s' "$(backup_site_root "$1")" "$2"
}

backup_resolve_id() {
  local site="$1" requested="$2"
  if [[ "$requested" != "latest" ]]; then
    printf '%s' "$requested"
    return 0
  fi

  local sr latest
  sr="$(backup_site_root "$site")"
  [[ -d "$sr" ]] || die "Chưa có backup cho site: $site"
  latest="$(find "$sr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | head -n1)"
  [[ -n "$latest" ]] || die "Không tìm thấy backup mới nhất: $site"
  printf '%s' "$latest"
}

backup_resolve_site_path() {
  local site="$1" path
  path="$(inventory_get_field "$site" path 2>/dev/null || true)"
  [[ -n "$path" && -d "$path" ]] || die "Không tìm thấy site/path: $site"
  readlink -f "$path"
}

backup_manifest_field() {
  local dir="$1" field="$2"
  python3 - "$dir/manifest.json" "$field" <<'PY'
import json,sys
p,field=sys.argv[1:]
with open(p,encoding="utf-8") as f:d=json.load(f)
v=d
for part in field.split("."):
    if not isinstance(v,dict):
        v=None; break
    v=v.get(part)
if v is None:
    print("")
elif isinstance(v,bool):
    print("1" if v else "0")
else:
    print(v)
PY
}

backup_manifest_write() {
  local site="$1" project="$2" out="$3"
  local domain http socket db repo branch commit compose
  domain="$(inventory_get_field "$site" domain 2>/dev/null || true)"
  http="$(inventory_get_field "$site" http_port 2>/dev/null || true)"
  socket="$(inventory_get_field "$site" socket_port 2>/dev/null || true)"
  db="$(inventory_get_field "$site" database 2>/dev/null || true)"
  repo="$(platform_git_remote "$project" 2>/dev/null || true)"
  branch="$(platform_git_branch "$project" 2>/dev/null || true)"
  commit="$(platform_git_commit "$project" 2>/dev/null || true)"
  compose="$(sed -n -E 's/^COMPOSE_PROJECT_NAME=(.*)$/\1/p' "$project/.docker-platform.env" 2>/dev/null | tail -n1)"

  python3 - "$out/manifest.json" "$site" "$project" "$domain" "$http" "$socket" "$db" "$repo" "$branch" "$commit" "$compose" <<'PY'
import json,sys,datetime,os
f,site,path,domain,http,socket,db,repo,branch,commit,compose=sys.argv[1:]
root=os.path.dirname(f)
files={}
for n in ("source.tar.gz","database.sql.gz","storage.tar.gz"):
    p=os.path.join(root,n)
    files[n]={
        "present":os.path.isfile(p),
        "size":os.path.getsize(p) if os.path.isfile(p) else 0
    }
d={
 "schema_version":1,
 "site":site,
 "created_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "path":path,
 "domain":domain or None,
 "http_port":int(http) if http.isdigit() else None,
 "socket_port":int(socket) if socket.isdigit() else None,
 "database":db or None,
 "repo":repo or None,
 "branch":branch or None,
 "commit":commit or None,
 "compose_project_name":compose or None,
 "files":files
}
with open(f,"w",encoding="utf-8") as h:
    json.dump(d,h,ensure_ascii=False,indent=2);h.write("\n")
PY
}

backup_write_checksums() {
  local out="$1"
  (
    cd "$out"
    : > CHECKSUMS.sha256
    for f in source.tar.gz database.sql.gz storage.tar.gz manifest.json; do
      [[ -f "$f" ]] && sha256sum "$f" >> CHECKSUMS.sha256
    done
  )
}

backup_create() {
  require_root
  require_command tar
  require_command gzip
  require_command sha256sum

  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform backup create <site>"

  local src=1 db=1 storage=1 a
  for a in "$@"; do
    case "$a" in
      --no-source) src=0 ;;
      --no-database) db=0 ;;
      --no-storage) storage=0 ;;
      *) die "Option không hợp lệ: $a" ;;
    esac
  done

  local project id out tmp
  project="$(backup_resolve_site_path "$site")"
  platform_git_verify "$project"

  id="$(backup_timestamp)"
  out="$(backup_dir "$site" "$id")"
  mkdir -p "$out"

  echo "[01/05] Backup source"
  if [[ "$src" -eq 1 ]]; then
    tar -C "$project" \
      --exclude='./.git' \
      --exclude='./vendor' \
      --exclude='./node_modules' \
      --exclude='./storage/logs' \
      -czf "$out/source.tar.gz" .
  else
    echo "[SKIP] source"
  fi

  echo "[02/05] Backup database"
  if [[ "$db" -eq 1 ]]; then
    [[ -x "$project/platform-cli" ]] || die "Thiếu platform-cli."
    tmp="/tmp/${site}_backup_$$.sql"
    PROJECT_DIR="$project" "$project/platform-cli" db export "$tmp"
    [[ -s "$tmp" ]] || die "Database dump rỗng."
    gzip -c "$tmp" > "$out/database.sql.gz"
    rm -f "$tmp"
  else
    echo "[SKIP] database"
  fi

  echo "[03/05] Backup storage"
  if [[ "$storage" -eq 1 ]]; then
    if [[ -d "$project/storage/app" ]]; then
      tar -C "$project/storage" -czf "$out/storage.tar.gz" app
    else
      echo "[WARN] storage/app không tồn tại."
    fi
  else
    echo "[SKIP] storage"
  fi

  echo "[04/05] Write manifest"
  backup_manifest_write "$site" "$project" "$out"

  echo "[05/05] Write checksums"
  backup_write_checksums "$out"

  backup_verify "$site" "$id" >/dev/null
  success "Backup hoàn tất: $out"
  echo "$id"
}

backup_list() {
  local site="${1:-}" root
  root="$(backup_root)"
  if [[ -n "$site" ]]; then
    local sr
    sr="$(backup_site_root "$site")"
    [[ -d "$sr" ]] || { echo "Chưa có backup: $site"; return 0; }
    find "$sr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r
  else
    [[ -d "$root" ]] || { echo "Chưa có backup."; return 0; }
    find "$root" -mindepth 2 -maxdepth 2 -type d -printf '%P\n' | sort
  fi
}

backup_show() {
  local site="${1:-}" id="${2:-}"
  [[ -n "$site" && -n "$id" ]] || die "USAGE: platform backup show <site> <backup-id>"
  id="$(backup_resolve_id "$site" "$id")"
  local f="$(backup_dir "$site" "$id")/manifest.json"
  [[ -f "$f" ]] || die "Không tìm thấy manifest: $f"
  cat "$f"
}

backup_verify() {
  local site="${1:-}" id="${2:-}"
  [[ -n "$site" && -n "$id" ]] || die "USAGE: platform backup verify <site> <backup-id>"
  id="$(backup_resolve_id "$site" "$id")"
  local d
  d="$(backup_dir "$site" "$id")"
  [[ -f "$d/manifest.json" && -f "$d/CHECKSUMS.sha256" ]] || die "Backup thiếu manifest/checksum."
  (cd "$d"; sha256sum -c CHECKSUMS.sha256)
  success "Backup hợp lệ: $site/$id"
}

backup_prune() {
  require_root
  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform backup prune <site> --keep=<count>"
  local keep="" a
  for a in "$@"; do
    case "$a" in
      --keep=*) keep="${a#*=}" ;;
      *) die "Option không hợp lệ: $a" ;;
    esac
  done
  [[ "$keep" =~ ^[0-9]+$ ]] || die "--keep phải là số."
  (( keep >= 1 )) || die "--keep phải >= 1."

  local sr
  sr="$(backup_site_root "$site")"
  [[ -d "$sr" ]] || return 0

  mapfile -t arr < <(find "$sr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
  local i
  for ((i=keep;i<${#arr[@]};i++)); do
    rm -rf "$sr/${arr[$i]}"
    echo "[OK] Removed: ${arr[$i]}"
  done
}

backup_restore_dns_check() {
  local domain="$1"
  if ! command -v getent >/dev/null 2>&1; then
    echo "[WARN] Không có getent; bỏ DNS resolve check."
    return 0
  fi

  local resolved
  resolved="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true)"
  if [[ -z "$resolved" ]]; then
    die "Domain chưa resolve được: $domain"
  fi

  echo "[OK] DNS resolve: $domain -> $resolved"
  echo "[INFO] Nếu Cloudflare Proxy đang bật, IP resolve là Cloudflare; đây là kết quả hợp lệ và không thể so trực tiếp với IP origin VPS."
}

backup_restore_database_inventory_owner() {
  local database="$1" ignore_site="${2:-}"
  python3 - "$(inventory_file)" "$database" "$ignore_site" <<'PY'
import json,sys
path,db,ignore=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
for s in d.get("sites",[]):
    if s.get("database")==db and s.get("name")!=ignore:
        print(s.get("name",""))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

backup_restore_domain_inventory_owner() {
  local domain="$1" ignore_site="${2:-}"
  python3 - "$(inventory_file)" "$domain" "$ignore_site" <<'PY'
import json,sys
path,domain,ignore=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
for s in d.get("sites",[]):
    if s.get("domain")==domain and s.get("name")!=ignore:
        print(s.get("name",""))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

backup_restore_extract_source() {
  local backup_dir="$1" target="$2"
  [[ -f "$backup_dir/source.tar.gz" ]] || die "Backup không có source.tar.gz"

  mkdir -p "$target"

  # Preserve target identity/runtime files that are configured later.
  tar -xzf "$backup_dir/source.tar.gz" -C "$target"
}

backup_restore_extract_storage() {
  local backup_dir="$1" target="$2"
  [[ -f "$backup_dir/storage.tar.gz" ]] || die "Backup không có storage.tar.gz"
  mkdir -p "$target/storage"
  tar -xzf "$backup_dir/storage.tar.gz" -C "$target/storage"
}

backup_restore_import_database() {
  local backup_dir="$1" target="$2"
  [[ -f "$backup_dir/database.sql.gz" ]] || die "Backup không có database.sql.gz"
  [[ -x "$target/platform-cli" ]] || die "Target thiếu platform-cli: $target/platform-cli"

  local tmp="/tmp/platform-restore-db-$$.sql"
  trap 'rm -f "$tmp"' RETURN

  gzip -dc "$backup_dir/database.sql.gz" > "$tmp"
  [[ -s "$tmp" ]] || die "SQL restore rỗng."

  PROJECT_DIR="$target" "$target/platform-cli" db import "$tmp" <<<"y"
  rm -f "$tmp"
  trap - RETURN
}

backup_restore_report() {
  local source_site="$1" backup_id="$2" target_site="$3" target_path="$4" domain="$5" database="$6" mode="$7"
  local dir="$PLATFORM_HOME/state/restore-history"
  mkdir -p "$dir"
  local file="$dir/$(date +%Y%m%d_%H%M%S)-$(backup_slugify "$target_site").json"

  python3 - "$file" "$source_site" "$backup_id" "$target_site" "$target_path" "$domain" "$database" "$mode" <<'PY'
import json,sys,datetime
file,source,backup,target,path,domain,database,mode=sys.argv[1:]
d={
 "status":"success",
 "completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "source_site":source,
 "backup_id":backup,
 "target_site":target,
 "target_path":path,
 "domain":domain,
 "database":database,
 "mode":mode
}
with open(file,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n")
print(file)
PY
}

backup_restore() {
  require_root
  require_command python3
  require_command tar
  require_command gzip

  local source_site="${1:-}"
  local requested_id="${2:-}"
  shift 2 || true

  [[ -n "$source_site" && -n "$requested_id" ]] || die \
    "USAGE: platform backup restore <site> <backup-id|latest> [options]"

  local new_domain="" new_database="" as_site="" target_path=""
  local http_port="auto" socket_port="auto"
  local dry_run=0 auto_yes=0 emergency=1 ssl=1 dns_check=1 overwrite_db=0
  local restore_source=1 restore_database=1 restore_storage=1
  local only_count=0 arg

  for arg in "$@"; do
    case "$arg" in
      --domain=*) new_domain="${arg#*=}" ;;
      --database=*) new_database="${arg#*=}" ;;
      --as=*) as_site="${arg#*=}" ;;
      --path=*) target_path="${arg#*=}" ;;
      --http-port=*) http_port="${arg#*=}" ;;
      --socket-port=*) socket_port="${arg#*=}" ;;
      --source-only)
        restore_source=1; restore_database=0; restore_storage=0; only_count=$((only_count+1)) ;;
      --database-only)
        restore_source=0; restore_database=1; restore_storage=0; only_count=$((only_count+1)) ;;
      --storage-only)
        restore_source=0; restore_database=0; restore_storage=1; only_count=$((only_count+1)) ;;
      --no-emergency-backup) emergency=0 ;;
      --no-ssl) ssl=0 ;;
      --skip-dns-check) dns_check=0 ;;
      --overwrite-database) overwrite_db=1 ;;
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  (( only_count <= 1 )) || die "Chỉ dùng một trong --source-only/--database-only/--storage-only."

  local backup_id bdir
  backup_id="$(backup_resolve_id "$source_site" "$requested_id")"
  bdir="$(backup_dir "$source_site" "$backup_id")"

  echo "[RESTORE 01/10] Verify backup"
  backup_verify "$source_site" "$backup_id"

  local manifest_domain manifest_database manifest_path
  manifest_domain="$(backup_manifest_field "$bdir" domain)"
  manifest_database="$(backup_manifest_field "$bdir" database)"
  manifest_path="$(backup_manifest_field "$bdir" path)"

  local target_site mode existing=1 old_domain="" old_database="" old_path=""
  if [[ -n "$as_site" ]]; then
    mode="restore-as-new"
    target_site="$as_site"
    existing=0
    [[ -n "$new_domain" ]] || die "--as yêu cầu --domain mới."
    site_assert_name_available "$target_site"
    site_assert_domain_available "$new_domain"
    target_path="${target_path:-$(site_projects_root)/$(site_slugify "$target_site")}"
    [[ ! -e "$target_path" ]] || die "Target path đã tồn tại: $target_path"
    new_database="${new_database:-db_$(site_slugify "$target_site" | tr '-' '_')}"
  else
    mode="restore-existing"
    target_site="$source_site"
    old_path="$(inventory_get_field "$target_site" path)"
    old_domain="$(inventory_get_field "$target_site" domain)"
    old_database="$(inventory_get_field "$target_site" database)"
    target_path="$old_path"
    new_domain="${new_domain:-$old_domain}"
    new_database="${new_database:-$old_database}"
  fi

  [[ -n "$new_domain" ]] || new_domain="$manifest_domain"
  [[ -n "$new_database" ]] || new_database="$manifest_database"

  platform_nginx_validate_domain "$new_domain"

  echo "[RESTORE 02/10] Preflight target identity"

  local owner=""
  owner="$(backup_restore_domain_inventory_owner "$new_domain" "$target_site" 2>/dev/null || true)"
  [[ -z "$owner" ]] || die "Domain $new_domain đang thuộc Inventory site: $owner"

  owner="$(backup_restore_database_inventory_owner "$new_database" "$target_site" 2>/dev/null || true)"
  [[ -z "$owner" ]] || die "Database $new_database đang thuộc Inventory site: $owner"

  if [[ "$dns_check" -eq 1 ]]; then
    backup_restore_dns_check "$new_domain"
  else
    echo "[INFO] DNS check skipped."
  fi

  if [[ "$new_domain" != "${old_domain:-}" || "$existing" -eq 0 ]]; then
    local conflicts
    conflicts="$(platform_nginx_conflict_files "$new_domain" || true)"
    if [[ -n "$conflicts" ]]; then
      die "Nginx server_name conflict: $conflicts"
    fi
  fi

  local resolved_http="" resolved_socket="" docker_identity=""
  if [[ "$existing" -eq 1 ]]; then
    resolved_http="$(inventory_get_field "$target_site" http_port)"
    resolved_socket="$(inventory_get_field "$target_site" socket_port)"
    docker_identity="$(sed -n -E 's/^COMPOSE_PROJECT_NAME=(.*)$/\1/p' "$target_path/.docker-platform.env" | tail -n1)"
    docker_identity="${docker_identity:-$(site_slugify "$target_site")}"
  else
    resolved_http="$(site_choose_port "$http_port" 8081)"
    resolved_socket="$(site_choose_port "$socket_port" 6001)"
    docker_identity="$(site_slugify "$target_site")"
  fi

  echo "Mode        : $mode"
  echo "Backup      : $source_site/$backup_id"
  echo "Target site : $target_site"
  echo "Target path : $target_path"
  echo "Domain      : $manifest_domain -> $new_domain"
  echo "Database    : $manifest_database -> $new_database"
  echo "HTTP port   : $resolved_http"
  echo "Socket port : $resolved_socket"
  echo "Docker name : $docker_identity"
  echo "Source      : $restore_source"
  echo "Database    : $restore_database"
  echo "Storage     : $restore_storage"
  echo "Emergency   : $emergency"
  echo "SSL         : $ssl"

  [[ "$dry_run" -eq 0 ]] || {
    echo "[DRY-RUN] Không thay đổi hệ thống."
    return 0
  }

  if [[ "$auto_yes" -eq 0 ]]; then
    local answer
    read -r -p "Restore backup này? [y/N]: " answer
    [[ "$answer" =~ ^[Yy]$ ]] || die "Đã hủy."
  fi

  local emergency_id="" committed=0 nginx_new=0
  trap 'rc=$?
        if [[ $rc -ne 0 ]]; then
          warn "Restore thất bại."
          if [[ "$existing" -eq 0 && "$committed" -eq 0 ]]; then
            site_provision_cleanup_new_target "$target_path" "$new_domain" "$nginx_new"
          elif [[ -n "$emergency_id" ]]; then
            warn "Emergency backup đã được tạo: $target_site/$emergency_id"
            warn "Không auto-restore emergency snapshot để tránh rollback chồng rollback."
          fi
        fi
        exit $rc' ERR

  echo "[RESTORE 03/10] Emergency backup"
  if [[ "$existing" -eq 1 && "$emergency" -eq 1 ]]; then
    emergency_id="$(backup_create "$target_site" | tail -n1)"
    echo "[OK] Emergency backup: $target_site/$emergency_id"
  else
    echo "[SKIP] Emergency backup"
  fi

  echo "[RESTORE 04/10] Restore source"
  if [[ "$restore_source" -eq 1 ]]; then
    if [[ "$existing" -eq 1 ]]; then
      # Preserve identity files, Git metadata and runtime wrapper while replacing app snapshot.
      local preserve_dir
      preserve_dir="$(mktemp -d /tmp/platform-restore-preserve.XXXXXX)"
      cp -a "$target_path/.env" "$preserve_dir/.env" 2>/dev/null || true
      cp -a "$target_path/.docker-platform.env" "$preserve_dir/.docker-platform.env" 2>/dev/null || true
      cp -a "$target_path/.git" "$preserve_dir/.git" 2>/dev/null || true

      rsync -a --delete \
        --exclude='.git' \
        --exclude='.env' \
        --exclude='.docker-platform.env' \
        --exclude='storage/app' \
        "$target_path/" "$target_path/" >/dev/null 2>&1 || true

      backup_restore_extract_source "$bdir" "$target_path"

      [[ -f "$preserve_dir/.env" ]] && cp -a "$preserve_dir/.env" "$target_path/.env"
      [[ -f "$preserve_dir/.docker-platform.env" ]] && cp -a "$preserve_dir/.docker-platform.env" "$target_path/.docker-platform.env"
      [[ -d "$preserve_dir/.git" ]] && { rm -rf "$target_path/.git"; cp -a "$preserve_dir/.git" "$target_path/.git"; }
      rm -rf "$preserve_dir"
    else
      mkdir -p "$target_path"
      backup_restore_extract_source "$bdir" "$target_path"
      # Snapshot source intentionally excludes .git; copy Git metadata from current source site if available.
      local current_source_path
      current_source_path="$(inventory_get_field "$source_site" path 2>/dev/null || true)"
      if [[ -n "$current_source_path" && -d "$current_source_path/.git" ]]; then
        platform_git_copy_metadata "$current_source_path" "$target_path"
      fi
    fi
  else
    echo "[SKIP] source"
  fi

  echo "[RESTORE 05/10] Configure target"
  site_provision_configure_target \
    "$target_path" "$target_site" "$new_domain" "$new_database" \
    "$resolved_http" "$resolved_socket" "$([[ "$existing" -eq 0 ]] && echo 1 || echo 0)"

  echo "[RESTORE 06/10] Prepare runtime"
  site_provision_prepare_runtime "$target_site" "$target_path" 0 120

  echo "[RESTORE 07/10] Restore database/storage"
  if [[ "$restore_database" -eq 1 ]]; then
    if [[ "$existing" -eq 0 && "$overwrite_db" -eq 0 ]]; then
      # platform-cli import is allowed only after target DB is newly provisioned by compose.
      # Inventory ownership was already checked above.
      :
    fi
    backup_restore_import_database "$bdir" "$target_path"
  else
    echo "[SKIP] database"
  fi

  if [[ "$restore_storage" -eq 1 ]]; then
    backup_restore_extract_storage "$bdir" "$target_path"
  else
    echo "[SKIP] storage"
  fi

  echo "[RESTORE 08/10] Deploy finalize"
  site_provision_finalize_runtime "$target_path"

  echo "[RESTORE 09/10] Nginx / SSL / Health"
  if [[ "$new_domain" != "${old_domain:-}" || "$existing" -eq 0 ]]; then
    platform_nginx_ensure_proxy "$new_domain" "$resolved_http"
    nginx_new=1
  fi

  if [[ "$ssl" -eq 1 ]]; then
    if platform_ssl_exists "$new_domain"; then
      platform_ssl_verify "$new_domain"
    else
      platform_ssl_issue "$new_domain"
    fi
  else
    echo "[INFO] SSL skipped."
  fi

  site_provision_health "$target_path"

  echo "[RESTORE 10/10] Inventory commit + report"
  site_provision_commit_inventory "$target_site" "$target_path"
  committed=1
  trap - ERR

  local report
  report="$(backup_restore_report "$source_site" "$backup_id" "$target_site" "$target_path" "$new_domain" "$new_database" "$mode")"

  success "Restore hoàn tất: $target_site"
  echo "Report: $report"
}
