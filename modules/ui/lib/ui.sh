#!/usr/bin/env bash

UI_PLATFORM_BIN="${UI_PLATFORM_BIN:-$PLATFORM_HOME/bin/platform}"

ui_clear() {
  if [[ -t 1 ]]; then
    printf '\033[2J\033[H'
  fi
}

ui_line() {
  printf '%s\n' "========================================================="
}

ui_header() {
  ui_clear
  ui_line
  printf ' Laravel Deployment Platform 2.1 — Simple Menu\n'
  ui_line
}

ui_section() {
  printf '\n----- %s -----\n' "$1"
}

ui_pause() {
  printf '\n'
  read -r -p "Nhấn Enter để tiếp tục..." _
}

ui_prompt() {
  local label="$1" default="${2:-}" value
  if [[ -n "$default" ]]; then
    read -r -p "$label [$default]: " value
    printf '%s' "${value:-$default}"
  else
    read -r -p "$label: " value
    printf '%s' "$value"
  fi
}

ui_yesno() {
  local label="$1" default="${2:-N}" value prompt
  if [[ "$default" =~ ^[Yy]$ ]]; then prompt="[Y/n]"; else prompt="[y/N]"; fi
  read -r -p "$label $prompt: " value
  [[ -z "$value" ]] && value="$default"
  [[ "$value" =~ ^[Yy]$ ]]
}

ui_confirm_execute() {
  local title="$1"
  printf '\n'
  ui_line
  printf '%s\n' "$title"
  ui_line
  ui_yesno "Thực hiện?" "N"
}

ui_run() {
  printf '\n> platform-v2'
  printf ' %q' "$@"
  printf '\n\n'
  "$UI_PLATFORM_BIN" "$@"
}

ui_run_sudo() {
  # The whole UI is normally run by sudo. Avoid nested sudo.
  ui_run "$@"
}

ui_inventory_sites_tsv() {
  inventory_init
  python3 - "$(inventory_file)" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:
    d=json.load(f)
for s in d.get("sites",[]):
    print("\t".join([
        str(s.get("name","")),
        str(s.get("domain","")),
        str(s.get("database","")),
        str(s.get("path",""))
    ]))
PY
}

ui_select_site() {
  local prompt="${1:-Chọn site}" rows=()
  mapfile -t rows < <(ui_inventory_sites_tsv)
  if [[ "${#rows[@]}" -eq 0 ]]; then
    echo "[WARN] Inventory chưa có active site." >&2
    return 1
  fi

  printf '\n%s\n\n' "$prompt" >&2
  local i name domain db path
  for i in "${!rows[@]}"; do
    IFS=$'\t' read -r name domain db path <<<"${rows[$i]}"
    printf '  %d) %-20s %s\n' "$((i+1))" "$name" "$domain" >&2
  done
  printf '  0) Cancel\n\n' >&2

  local choice
  read -r -p "Chọn: " choice
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#rows[@]} )) || return 1

  IFS=$'\t' read -r name domain db path <<<"${rows[$((choice-1))]}"
  printf '%s' "$name"
}

ui_backup_ids() {
  local site="$1"
  "$UI_PLATFORM_BIN" backup list "$site" 2>/dev/null || true
}

ui_select_backup() {
  local site="$1" rows=()
  mapfile -t rows < <(ui_backup_ids "$site" | grep -E '^[0-9]{8}_[0-9]{6}$' || true)
  [[ "${#rows[@]}" -gt 0 ]] || {
    echo "[WARN] Không có backup cho $site." >&2
    return 1
  }

  printf '\nChọn backup của %s:\n\n' "$site" >&2
  local i
  for i in "${!rows[@]}"; do
    printf '  %d) %s\n' "$((i+1))" "${rows[$i]}" >&2
  done
  printf '  L) latest\n  0) Cancel\n\n' >&2

  local choice
  read -r -p "Chọn: " choice
  [[ "$choice" =~ ^[Ll]$ ]] && { printf 'latest'; return 0; }
  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  (( choice >= 1 && choice <= ${#rows[@]} )) || return 1
  printf '%s' "${rows[$((choice-1))]}"
}

ui_main() {
  while true; do
    ui_header
    cat <<'EOF'

  1) Sites
  2) Backup / Restore
  3) Deploy
  4) Domain / Doctor
  5) Infrastructure (Nginx / SSL)
  6) Packages

  0) Exit

EOF
    local choice
    read -r -p "Chọn chức năng: " choice
    case "$choice" in
      1) ui_menu_sites ;;
      2) ui_menu_backup ;;
      3) ui_menu_deploy ;;
      4) ui_menu_doctor ;;
      5) ui_menu_infrastructure ;;
      6) ui_menu_packages ;;
      0|q|Q) return 0 ;;
      *) ;;
    esac
  done
}


ui_dns_resolve_ipv4() {
  local domain="$1"
  if ! command -v getent >/dev/null 2>&1; then
    printf ''
    return 0
  fi
  getent ahostsv4 "$domain" 2>/dev/null |
    awk '{print $1}' |
    sort -u |
    paste -sd, - || true
}

ui_ssl_exists() {
  local domain="$1"
  "$UI_PLATFORM_BIN" ssl verify "$domain" >/dev/null 2>&1
}

ui_restore_ssl_gate() {
  # Output mode through global UI_RESTORE_SSL_MODE:
  # normal | no-ssl | cancel
  local domain="$1"
  UI_RESTORE_SSL_MODE="normal"

  if ui_ssl_exists "$domain"; then
    printf '\n[OK] SSL đã tồn tại và verify được: %s\n' "$domain"
    return 0
  fi

  while true; do
    local ips
    ips="$(ui_dns_resolve_ipv4 "$domain")"

    printf '\n'
    ui_line
    printf ' SSL CHƯA CÓ — DOMAIN PRECHECK\n'
    ui_line
    printf 'Domain       : %s\n' "$domain"
    printf 'DNS hiện tại : %s\n' "${ips:-KHÔNG RESOLVE}"
    printf '\n'
    printf 'Nếu domain đang bật Cloudflare Proxy màu cam, Certbot HTTP-01\n'
    printf 'có thể thất bại. Bạn có thể chuyển record sang DNS only trước.\n'
    printf '\n'
    cat <<'EOF'
  1) Tôi đã chuyển DNS only → kiểm tra DNS lại
  2) Tiếp tục Restore và cấp SSL bình thường
  3) Restore không SSL (--no-ssl)
  4) Chạy Doctor domain
  0) Hủy Restore
EOF
    printf '\n'

    local c
    read -r -p "Chọn: " c
    case "$c" in
      1)
        printf '\n[INFO] Đợi DNS cập nhật. Nhấn Enter khi muốn kiểm tra lại.\n'
        read -r _
        local new_ips
        new_ips="$(ui_dns_resolve_ipv4 "$domain")"
        printf '[INFO] DNS hiện tại: %s\n' "${new_ips:-KHÔNG RESOLVE}"
        if [[ -n "$new_ips" && "$new_ips" != "$ips" ]]; then
          printf '[OK] DNS đã thay đổi so với lần kiểm tra trước.\n'
          if ui_yesno "Tiếp tục Restore với SSL?" "Y"; then
            UI_RESTORE_SSL_MODE="normal"
            return 0
          fi
        else
          printf '[WARN] DNS chưa thay đổi hoặc chưa resolve.\n'
        fi
        ;;
      2)
        UI_RESTORE_SSL_MODE="normal"
        return 0
        ;;
      3)
        UI_RESTORE_SSL_MODE="no-ssl"
        return 0
        ;;
      4)
        ui_run_sudo doctor domain "$domain" || true
        ui_pause
        ;;
      0)
        UI_RESTORE_SSL_MODE="cancel"
        return 1
        ;;
    esac
  done
}

ui_command_failed() {
  local label="$1"
  printf '\n[ERROR] %s thất bại.\n' "$label"
  printf '[INFO] Platform đã in chi tiết lỗi ở phía trên.\n'
}


ui_state_root() {
  printf '%s' "$PLATFORM_HOME/state/ui"
}

ui_restore_state_file() {
  printf '%s/restore-last.json' "$(ui_state_root)"
}

ui_restore_state_exists() {
  [[ -f "$(ui_restore_state_file)" ]]
}

ui_restore_state_save() {
  local mode="$1"
  local source="$2"
  local backup="$3"
  local target_site="$4"
  local domain="$5"
  local database="$6"
  local ssl_mode="${7:-normal}"

  local file
  file="$(ui_restore_state_file)"
  mkdir -p "$(dirname "$file")"

  python3 - "$file" "$mode" "$source" "$backup" "$target_site" "$domain" "$database" "$ssl_mode" <<'PY'
import json,sys,datetime,os,tempfile
file,mode,source,backup,target,domain,database,ssl_mode=sys.argv[1:]
data={
  "schema_version":1,
  "operation":"restore",
  "mode":mode,
  "source_site":source,
  "backup":backup,
  "target_site":target,
  "domain":domain or None,
  "database":database or None,
  "ssl_mode":ssl_mode,
  "status":"pending",
  "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()
}
os.makedirs(os.path.dirname(file),exist_ok=True)
fd,tmp=tempfile.mkstemp(prefix=".restore-state.",dir=os.path.dirname(file))
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

ui_restore_state_mark_failed() {
  local message="${1:-restore failed}"
  local file
  file="$(ui_restore_state_file)"
  [[ -f "$file" ]] || return 0

  python3 - "$file" "$message" <<'PY'
import json,sys,datetime,os,tempfile
file,msg=sys.argv[1:]
try:
    with open(file,encoding="utf-8") as f:d=json.load(f)
except Exception:
    raise SystemExit(0)
d["status"]="failed"
d["last_error"]=msg
d["updated_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
fd,tmp=tempfile.mkstemp(prefix=".restore-state.",dir=os.path.dirname(file))
try:
    with os.fdopen(fd,"w",encoding="utf-8") as f:
        json.dump(d,f,ensure_ascii=False,indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp,file)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY
}

ui_restore_state_clear() {
  rm -f "$(ui_restore_state_file)"
}

ui_restore_state_show() {
  local file
  file="$(ui_restore_state_file)"
  [[ -f "$file" ]] || return 1

  python3 - "$file" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
print("Pending Restore")
print("---------------")
print(f"Mode       : {d.get('mode','')}")
print(f"Source     : {d.get('source_site','')}")
print(f"Backup     : {d.get('backup','')}")
print(f"Target     : {d.get('target_site','')}")
print(f"Domain     : {d.get('domain') or 'N/A'}")
print(f"Database   : {d.get('database') or 'N/A'}")
print(f"SSL mode   : {d.get('ssl_mode','normal')}")
print(f"Status     : {d.get('status','pending')}")
print(f"Updated    : {d.get('updated_at','')}")
PY
}

ui_restore_state_field() {
  local field="$1"
  local file
  file="$(ui_restore_state_file)"
  [[ -f "$file" ]] || return 1
  python3 - "$file" "$field" <<'PY'
import json,sys
with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
v=d.get(sys.argv[2])
print("" if v is None else v)
PY
}


ui_ssl_setup() {
  local domain="${1:-}"
  if [[ -z "$domain" ]]; then
    domain="$(ui_prompt "Domain cần SSL")"
  fi

  [[ -n "$domain" ]] || {
    echo "[ERROR] Domain bắt buộc."
    return 1
  }

  ui_section "SSL SETUP"
  echo "Domain : $domain"
  echo

  echo "[01/04] Check existing certificate"
  if ui_ssl_exists "$domain"; then
    echo "[OK] SSL đã tồn tại và hợp lệ: $domain"
    ui_run ssl show "$domain" || true
    return 0
  fi

  echo "[INFO] SSL chưa tồn tại hoặc chưa verify được."

  echo
  echo "[02/04] Domain preflight"
  ui_run_sudo doctor domain "$domain" || true

  echo
  echo "[03/04] DNS / SSL decision"
  if ! ui_restore_ssl_gate "$domain"; then
    echo "[INFO] Đã hủy SSL Setup."
    return 1
  fi

  local mode="${UI_RESTORE_SSL_MODE:-normal}"
  if [[ "$mode" == "no-ssl" ]]; then
    echo "[INFO] SSL Setup không có chế độ --no-ssl."
    echo "[INFO] Site hiện vẫn có thể chạy HTTP; bạn có thể tạo SSL sau."
    return 0
  fi

  ui_confirm_execute "ISSUE SSL: $domain" || {
    echo "[INFO] Đã hủy SSL Setup."
    return 1
  }

  if ! ui_run_sudo ssl issue "$domain"; then
    echo
    echo "[ERROR] Không tạo được SSL: $domain"
    echo "[INFO] Kiểm tra DNS, Nginx và port 80 rồi thử lại ngay trong Menu."
    return 1
  fi

  echo
  echo "[04/04] Verify certificate"
  if ui_run_sudo ssl verify "$domain"; then
    echo
    echo "[OK] SSL Setup hoàn tất: $domain"
    return 0
  fi

  echo "[ERROR] Certbot đã chạy nhưng verify certificate chưa đạt."
  return 1
}


ui_inventory_site_by_domain_json() {
  local domain="$1"
  inventory_init
  python3 - "$(inventory_file)" "$domain" <<'PY'
import json,sys
path,domain=sys.argv[1:]
with open(path,encoding="utf-8") as f:
    d=json.load(f)
for s in d.get("sites",[]):
    if str(s.get("domain","")) == domain:
        print(json.dumps(s,ensure_ascii=False))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

ui_json_field() {
  local raw="$1" field="$2"
  python3 - "$raw" "$field" <<'PY'
import json,sys
raw,field=sys.argv[1:]
try:
    d=json.loads(raw)
except Exception:
    print("")
    raise SystemExit(0)
v=d
for p in field.split("."):
    v=v.get(p) if isinstance(v,dict) else None
print("" if v is None else v)
PY
}

ui_ssl_status_summary() {
  local domain="$1"
  if ui_ssl_exists "$domain"; then
    printf 'VALID'
  else
    printf 'MISSING'
  fi
}

ui_nginx_enabled() {
  local domain="$1"
  [[ -L "/etc/nginx/sites-enabled/$domain" ]]
}

ui_site_runtime_running() {
  local path="$1"
  [[ -d "$path" ]] || return 1
  local count
  count="$("$UI_PLATFORM_BIN" deploy status "$path" 2>/dev/null | grep -c 'Up ' || true)"
  [[ "${count:-0}" -gt 0 ]]
}

ui_ssl_wizard_summary() {
  local domain="$1" site_json="$2"
  local name path database http_port socket_port dns ssl
  name="$(ui_json_field "$site_json" name)"
  path="$(ui_json_field "$site_json" path)"
  database="$(ui_json_field "$site_json" database)"
  http_port="$(ui_json_field "$site_json" http_port)"
  socket_port="$(ui_json_field "$site_json" socket_port)"
  dns="$(ui_dns_resolve_ipv4 "$domain")"
  ssl="$(ui_ssl_status_summary "$domain")"

  ui_line
  printf ' SSL WIZARD\n'
  ui_line
  printf 'Domain       : %s\n' "$domain"
  printf 'Site         : %s\n' "${name:-N/A}"
  printf 'Path         : %s\n' "${path:-N/A}"
  printf 'Database     : %s\n' "${database:-N/A}"
  printf 'HTTP port    : %s\n' "${http_port:-N/A}"
  printf 'Socket port  : %s\n' "${socket_port:-N/A}"
  printf 'DNS          : %s\n' "${dns:-KHÔNG RESOLVE}"

  if ui_nginx_enabled "$domain"; then
    printf 'Nginx        : ENABLED\n'
  else
    printf 'Nginx        : NOT ENABLED\n'
  fi

  if ui_site_runtime_running "$path"; then
    printf 'Runtime      : RUNNING\n'
  else
    printf 'Runtime      : NOT RUNNING / UNKNOWN\n'
  fi

  printf 'SSL          : %s\n' "$ssl"
  ui_line
}

ui_ssl_wizard_issue_loop() {
  local domain="$1"

  while true; do
    echo
    echo "Tạo SSL cho: $domain"
    echo
    cat <<'EOF'
  1) Create SSL
  2) Verify SSL again
  3) Show current SSL
  4) Check DNS again
  5) Show Nginx config
  6) Show Nginx conflicts
  7) Run Doctor domain
  0) Cancel
EOF
    echo

    local c
    read -r -p "Chọn: " c
    case "$c" in
      1)
        if ui_run_sudo ssl issue "$domain"; then
          echo
          echo "[INFO] Certbot issue hoàn tất. Đang verify..."
          if ui_run_sudo ssl verify "$domain"; then
            echo
            echo "[OK] SSL Wizard hoàn tất: $domain"
            ui_run ssl show "$domain" || true
            return 0
          fi
          echo "[ERROR] Certificate issue xong nhưng verify chưa đạt."
        else
          echo
          echo "[ERROR] SSL issue thất bại."
          echo "[INFO] Bạn có thể kiểm tra DNS/Nginx/Doctor ngay tại đây rồi Retry."
        fi
        ;;
      2)
        if ui_run_sudo ssl verify "$domain"; then
          echo "[OK] SSL hợp lệ: $domain"
          return 0
        fi
        ;;
      3)
        ui_run ssl show "$domain" || true
        ;;
      4)
        local ips
        ips="$(ui_dns_resolve_ipv4 "$domain")"
        echo "DNS hiện tại: ${ips:-KHÔNG RESOLVE}"
        ;;
      5)
        ui_run nginx show "$domain" || true
        ;;
      6)
        ui_run_sudo nginx conflicts "$domain" || true
        ;;
      7)
        ui_run_sudo doctor domain "$domain" || true
        ;;
      0)
        echo "[INFO] Đã hủy SSL Wizard."
        return 1
        ;;
    esac
  done
}

ui_ssl_wizard() {
  local domain="${1:-}"
  [[ -n "$domain" ]] || domain="$(ui_prompt "Domain cần SSL")"
  [[ -n "$domain" ]] || {
    echo "[ERROR] Domain bắt buộc."
    return 1
  }

  local site_json
  site_json="$(ui_inventory_site_by_domain_json "$domain" 2>/dev/null || true)"

  if [[ -z "$site_json" ]]; then
    ui_line
    echo "SSL WIZARD"
    ui_line
    echo "Domain : $domain"
    echo
    echo "[ERROR] Domain chưa thuộc site nào trong Inventory."
    echo
    cat <<'EOF'
  1) Run Doctor domain
  2) Show Nginx conflicts
  0) Cancel
EOF
    echo
    local c
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_run_sudo doctor domain "$domain" || true ;;
      2) ui_run_sudo nginx conflicts "$domain" || true ;;
    esac
    return 1
  fi

  ui_ssl_wizard_summary "$domain" "$site_json"

  if ui_ssl_exists "$domain"; then
    echo
    echo "[OK] Domain đã có SSL hợp lệ."
    echo
    cat <<'EOF'
  1) Show certificate
  2) Renew certificate
  0) Back
EOF
    echo

    local c
    read -r -p "Chọn: " c
    case "$c" in
      1) ui_run ssl show "$domain" || true ;;
      2)
        ui_confirm_execute "RENEW SSL: $domain" &&
          ui_run_sudo ssl renew "$domain"
        ;;
    esac
    return 0
  fi

  echo
  echo "[INFO] SSL chưa có. Không cần build/restore lại site."
  echo "[INFO] Wizard sẽ gọi trực tiếp SSL Module để cấp certificate."

  if ! ui_nginx_enabled "$domain"; then
    echo
    echo "[WARN] Nginx site hiện chưa enabled."
    echo "Bạn nên kiểm tra Nginx trước khi issue SSL."
  fi

  ui_ssl_wizard_issue_loop "$domain"
}
