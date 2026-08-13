#!/usr/bin/env bash

site_purge_history_root() {
  printf '%s' "$PLATFORM_HOME/state/site-lifecycle/purged"
}

site_purge_archive_file() {
  local site="$1"
  printf '%s/%s.json' "$PLATFORM_HOME/state/site-lifecycle/archived" "$(site_slugify "$site")"
}

site_purge_resolve_json() {
  local site="$1"
  local archived
  archived="$(site_purge_archive_file "$site")"

  if [[ -f "$archived" ]]; then
    python3 - "$archived" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
print(json.dumps({
 "source":"archive",
 "record":d.get("inventory_record",{}),
 "final_backup":d.get("final_backup")
},ensure_ascii=False))
PY
    return 0
  fi

  local inv
  inv="$(inventory_find_json "$site" 2>/dev/null || true)"
  [[ -n "$inv" ]] || die "Không tìm thấy active hoặc archived site: $site"

  python3 - "$inv" <<'PY'
import json,sys
print(json.dumps({"source":"inventory","record":json.loads(sys.argv[1]),"final_backup":None},
                 ensure_ascii=False))
PY
}

site_purge_json_field() {
  local raw="$1" field="$2"
  python3 - "$raw" "$field" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
v=d
for p in sys.argv[2].split("."):
    v=v.get(p) if isinstance(v,dict) else None
print("" if v is None else v)
PY
}

site_purge_latest_backup() {
  local site="$1"
  local root="${PLATFORM_BACKUP_ROOT:-/opt/backups/platform-v2}/$(site_slugify "$site")"
  [[ -d "$root" ]] || return 1
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | head -n1
}

site_purge_write_history() {
  local site="$1" domain="$2" database="$3" path="$4" backup="$5"
  local keep_source="$6" keep_volumes="$7" keep_ssl="$8"
  local root file
  root="$(site_purge_history_root)"
  mkdir -p "$root"
  file="$root/$(date +%Y%m%d_%H%M%S)-$(site_slugify "$site").json"

  python3 - "$file" "$site" "$domain" "$database" "$path" "$backup" \
    "$keep_source" "$keep_volumes" "$keep_ssl" <<'PY'
import json,sys,datetime
file,site,domain,database,path,backup,ks,kv,kssl=sys.argv[1:]
d={
 "schema_version":1,
 "site":site,
 "domain":domain,
 "database":database,
 "path":path,
 "backup":backup or None,
 "purged_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "kept":{"source":ks=="1","volumes":kv=="1","ssl":kssl=="1"}
}
with open(file,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2);f.write("\n")
print(file)
PY
}

site_purge_inventory_remove_if_present() {
  local site="$1"
  if inventory_find_json "$site" >/dev/null 2>&1; then
    site_lifecycle_inventory_remove "$site"
  fi
}

site_purge_source_is_managed() {
  local site="$1" path="$2"
  local canonical slug expected
  [[ -n "$path" ]] || return 1
  canonical="$(readlink -m -- "$path")"
  slug="$(site_slugify "$site")"
  expected="/opt/$slug/repo"

  case "$canonical" in
    /opt/projects/*) [[ "$canonical" != "/opt/projects" && "$canonical" != "/opt/projects/" ]] ;;
    "$expected") return 0 ;;
    *) return 1 ;;
  esac
}

site_purge_nginx_remove() {
  local domain="$1"
  [[ -n "$domain" ]] || return 0

  if ! platform_nginx_remove "$domain"; then
    platform_error "PURGE.NGINX_REMOVE_FAILED" "Không thể xoá Nginx config cho $domain. Archive/inventory được giữ nguyên để retry."
    return 1
  fi
}

site_purge() {
  require_root
  local site="${1:-}"; shift || true
  [[ -n "$site" ]] || die "USAGE: platform site purge <site> [options]"

  local dry_run=0 auto_yes=0 do_backup=1 force_active=0
  local keep_source=0 keep_volumes=0 keep_ssl=0 arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      --no-backup) do_backup=0 ;;
      --force-active) force_active=1 ;;
      --keep-source) keep_source=1 ;;
      --keep-volumes) keep_volumes=1 ;;
      --keep-ssl) keep_ssl=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  if [[ "$do_backup" -eq 0 && "$auto_yes" -ne 1 ]]; then
    die "--no-backup bắt buộc đi cùng --yes."
  fi
  if [[ "$force_active" -eq 1 && "$auto_yes" -ne 1 && "$dry_run" -ne 1 ]]; then
    die "--force-active bắt buộc đi cùng --yes khi thực thi."
  fi

  local resolved source_type path domain database backup_id=""
  resolved="$(site_purge_resolve_json "$site")"
  source_type="$(site_purge_json_field "$resolved" source)"
  path="$(site_purge_json_field "$resolved" record.path)"
  domain="$(site_purge_json_field "$resolved" record.domain)"
  database="$(site_purge_json_field "$resolved" record.database)"
  backup_id="$(site_purge_json_field "$resolved" final_backup)"

  if [[ "$source_type" == "inventory" && "$force_active" -ne 1 ]]; then
    platform_die "$PLATFORM_EXIT_CONFLICT" "PURGE.ACTIVE_REQUIRES_FORCE" \
      "Site '$site' đang active. Hãy Archive trước, hoặc dùng --force-active --yes để purge trực tiếp."
  fi

  echo "========================================================="
  echo "SITE PURGE PLAN"
  echo "Risk Level   : DESTRUCTIVE / PERMANENT"
  echo "========================================================="
  echo "Site         : $site"
  echo "State source : $source_type"
  echo "Domain       : ${domain:-N/A}"
  echo "Database     : ${database:-N/A}"
  echo "Path         : ${path:-N/A}"
  echo "Mode         : $([[ "$force_active" -eq 1 ]] && echo FORCE-ACTIVE || echo ARCHIVE)"
  echo "Backup       : $([[ "$do_backup" -eq 1 ]] && echo REQUIRED || echo SKIPPED)"
  echo "Keep source  : $keep_source"
  echo "Keep volumes : $keep_volumes"
  echo "Keep SSL     : $keep_ssl"
  echo
  echo "Will purge:"
  echo "  Containers/network : YES"
  echo "  Volumes             : $([[ "$keep_volumes" -eq 1 ]] && echo NO || echo YES)"
  echo "  Nginx config         : YES"
  echo "  SSL certificate      : $([[ "$keep_ssl" -eq 1 ]] && echo NO || echo YES)"
  echo "  Source               : $([[ "$keep_source" -eq 1 ]] && echo NO || echo YES)"
  echo "  Inventory/archive    : YES"
  echo "  Backups              : KEEP"
  echo "  Purge history        : KEEP"
  echo "========================================================="

  [[ "$dry_run" -eq 0 ]] || { echo "[DRY-RUN] Không thay đổi hệ thống."; return 0; }

  if [[ "$auto_yes" -eq 0 ]]; then
    local typed
    echo "CẢNH BÁO: purge không thể hoàn tác từ runtime."
    read -r -p "Nhập chính xác '$site' để xác nhận purge: " typed
    [[ "$typed" == "$site" ]] || die "Xác nhận không khớp."
  fi

  echo "[PURGE 01/08] Backup safety"
  if [[ "$do_backup" -eq 1 ]]; then
    command -v backup_verify >/dev/null 2>&1 || die "Backup helper chưa được nạp: backup_verify"
    if inventory_find_json "$site" >/dev/null 2>&1; then
      command -v platform_git_verify >/dev/null 2>&1 || die "Git helper chưa được nạp: platform_git_verify"
      command -v backup_create >/dev/null 2>&1 || die "Backup helper chưa được nạp: backup_create"
    fi
    if [[ -n "$backup_id" ]]; then
      backup_verify "$site" "$backup_id"
      echo "[OK] Archived final backup verified: $site/$backup_id"
    elif inventory_find_json "$site" >/dev/null 2>&1; then
      backup_id="$(backup_create "$site" | tail -n1)"
      backup_verify "$site" "$backup_id"
      echo "[OK] Final backup verified: $site/$backup_id"
    else
      backup_id="$(site_purge_latest_backup "$site" || true)"
      [[ -n "$backup_id" ]] || die "Không có backup cho archived site."
      backup_verify "$site" "$backup_id"
    fi
  else
    warn "PURGE WITHOUT BACKUP."
  fi

  echo "[PURGE 02/08] Nginx disable"
  if [[ -n "$domain" ]]; then
    platform_nginx_disable "$domain" || warn "Nginx disable không hoàn tất; tiếp tục remove config."
  fi

  echo "[PURGE 03/08] Docker runtime"
  if [[ -n "$path" && -d "$path" ]]; then
    if [[ "$keep_volumes" -eq 1 ]]; then
      deploy_compose "$path" down --remove-orphans || warn "Docker runtime cleanup có lỗi; tiếp tục purge."
    else
      deploy_compose "$path" down -v --remove-orphans || warn "Docker runtime/volume cleanup có lỗi; tiếp tục purge."
    fi
  else
    echo "[INFO] Source path absent; Docker compose cleanup skipped."
  fi

  echo "[PURGE 04/08] Nginx config"
  site_purge_nginx_remove "$domain" || return "$PLATFORM_EXIT_OPERATION"

  echo "[PURGE 05/08] SSL"
  if [[ "$keep_ssl" -eq 1 ]]; then
    echo "[KEEP] SSL"
  elif [[ -n "$domain" ]] && platform_ssl_exists "$domain"; then
    platform_ssl_remove "$domain"
  else
    echo "[INFO] No SSL to remove."
  fi

  echo "[PURGE 06/08] Source"
  if [[ "$keep_source" -eq 1 ]]; then
    echo "[KEEP] Source: $path"
  elif [[ -n "$path" && -e "$path" ]]; then
    if ! site_purge_source_is_managed "$site" "$path"; then
      platform_die "$PLATFORM_EXIT_CONFLICT" "PURGE.SOURCE_PATH_UNMANAGED" \
        "Refuse auto-purge source ngoài managed path: $path"
    fi
    rm -rf --one-file-system "$path"
  fi

  echo "[PURGE 07/08] Detach state"
  site_purge_inventory_remove_if_present "$site"
  rm -f "$(site_purge_archive_file "$site")"
  rm -f "$(site_lifecycle_state_file "$site")"

  echo "[PURGE 08/08] History"
  local report
  report="$(site_purge_write_history "$site" "$domain" "$database" "$path" "$backup_id" \
    "$keep_source" "$keep_volumes" "$keep_ssl")"

  success "Site purged: $site"
  [[ -n "$backup_id" ]] && echo "Recovery backup : $site/$backup_id"
  echo "History         : $report"
}
