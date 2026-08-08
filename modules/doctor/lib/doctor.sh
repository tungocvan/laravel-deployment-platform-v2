#!/usr/bin/env bash

doctor_ok()   { printf '[OK] %s\n' "$*"; }
doctor_info() { printf '[INFO] %s\n' "$*"; }
doctor_warn() { printf '[WARN] %s\n' "$*"; }
doctor_err()  { printf '[ERROR] %s\n' "$*"; }

doctor_inventory_site_json_by_field() {
  local field="$1" value="$2"
  [[ -n "$value" ]] || return 1
  inventory_init
  python3 - "$(inventory_file)" "$field" "$value" <<'PY'
import json,sys
path,field,value=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
for s in d.get("sites",[]):
    if str(s.get(field,"")) == value:
        print(json.dumps(s,ensure_ascii=False))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

doctor_json_field() {
  local json="$1" field="$2"
  python3 - "$json" "$field" <<'PY'
import json,sys
raw,field=sys.argv[1:]
try:d=json.loads(raw)
except Exception: print(""); raise SystemExit(0)
v=d.get(field)
print("" if v is None else v)
PY
}

doctor_inventory_owner_by_field() {
  local field="$1" value="$2"
  [[ -n "$value" ]] || return 1
  inventory_init
  python3 - "$(inventory_file)" "$field" "$value" <<'PY'
import json,sys
path,field,value=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
for s in d.get("sites",[]):
    if str(s.get(field,"")) == value:
        print(s.get("name",""))
        raise SystemExit(0)
for r in d.get("reserved_resources",[]):
    if str(r.get(field,"")) == value:
        print(r.get("name",""))
        raise SystemExit(0)
raise SystemExit(1)
PY
}

doctor_domain_dns() {
  local domain="$1"
  if ! command -v getent >/dev/null 2>&1; then
    doctor_warn "Không có getent; không kiểm tra được DNS."
    return 2
  fi

  local ips
  ips="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1}' | sort -u | paste -sd, - || true)"
  if [[ -z "$ips" ]]; then
    doctor_err "DNS chưa resolve: $domain"
    return 1
  fi

  doctor_ok "DNS resolve: $domain -> $ips"
  doctor_info "Cloudflare Proxy màu cam được hỗ trợ; IP resolve không cần trùng IP origin VPS."
}

doctor_backup_info() {
  local site="$1"
  local root="${PLATFORM_BACKUP_ROOT:-/opt/backups/platform-v2}"
  local site_dir="$root/$site"

  # Backup module slug convention.
  if [[ ! -d "$site_dir" ]]; then
    local slug
    slug="$(printf '%s' "$site" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g;s/^-+//;s/-+$//')"
    site_dir="$root/$slug"
  fi

  if [[ ! -d "$site_dir" ]]; then
    doctor_warn "Backup: chưa có backup cho site $site."
    return 0
  fi

  local count latest created=""
  count="$(find "$site_dir" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  latest="$(find "$site_dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r | head -n1)"

  if [[ -z "$latest" ]]; then
    doctor_warn "Backup: chưa có backup cho site $site."
    return 0
  fi

  if [[ -f "$site_dir/$latest/manifest.json" ]]; then
    created="$(python3 - "$site_dir/$latest/manifest.json" <<'PY'
import json,sys
try:
    with open(sys.argv[1],encoding="utf-8") as f:d=json.load(f)
    print(d.get("created_at",""))
except Exception:
    print("")
PY
)"
  fi

  doctor_ok "Backup: có $count bản."
  echo "       Latest backup : $latest"
  [[ -n "$created" ]] && echo "       Created       : $created"

  if [[ -f "$site_dir/$latest/CHECKSUMS.sha256" ]]; then
    if (cd "$site_dir/$latest" && sha256sum -c CHECKSUMS.sha256 >/dev/null 2>&1); then
      echo "       Latest verify  : OK"
    else
      echo "       Latest verify  : FAILED"
    fi
  else
    echo "       Latest verify  : NO CHECKSUM"
  fi
}

doctor_find_free_port_value() {
  local start="$1"
  inventory_find_free_port "$start"
}

doctor_check_requested_port() {
  local label="$1" requested="$2"
  if [[ ! "$requested" =~ ^[0-9]+$ ]] || (( requested < 1 || requested > 65535 )); then
    doctor_err "$label không hợp lệ: $requested"
    return 1
  fi
  if inventory_port_used "$requested"; then
    doctor_err "$label đang được sử dụng/reserved: $requested"
    return 1
  fi
  doctor_ok "$label khả dụng: $requested"
  return 0
}

doctor_domain() {
  local domain="${1:-}"
  shift || true
  [[ -n "$domain" ]] || die "USAGE: platform doctor domain <domain> [options]"

  local name="" database="" path=""
  local http_port="auto" socket_port="auto" dns_check=1
  local arg
  for arg in "$@"; do
    case "$arg" in
      --name=*) name="${arg#*=}" ;;
      --database=*) database="${arg#*=}" ;;
      --path=*) path="${arg#*=}" ;;
      --http-port=*) http_port="${arg#*=}" ;;
      --socket-port=*) socket_port="${arg#*=}" ;;
      --skip-dns-check) dns_check=0 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  local errors=0 warnings=0
  local existing_json="" existing_site="" existing_db="" existing_path=""
  local existing_http="" existing_socket=""
  local conflicts="" owner="" http_candidate="" socket_candidate=""

  echo "========================================================="
  echo "Laravel Deployment Platform — Domain Preflight"
  echo "========================================================="
  echo "Domain      : $domain"
  [[ -n "$name" ]] && echo "Site name   : $name"
  [[ -n "$database" ]] && echo "Database    : $database"
  echo

  echo "----- DOMAIN -----"

  if platform_nginx_validate_domain "$domain"; then
    doctor_ok "Domain syntax hợp lệ."
  else
    doctor_err "Domain syntax không hợp lệ: $domain"
    errors=$((errors+1))
  fi

  if [[ "$dns_check" -eq 1 ]]; then
    if doctor_domain_dns "$domain"; then
      :
    else
      rc=$?
      if [[ "$rc" -eq 1 ]]; then errors=$((errors+1)); else warnings=$((warnings+1)); fi
    fi
  else
    doctor_info "DNS check skipped."
  fi

  existing_json="$(doctor_inventory_site_json_by_field domain "$domain" 2>/dev/null || true)"
  if [[ -n "$existing_json" ]]; then
    existing_site="$(doctor_json_field "$existing_json" name)"
    existing_db="$(doctor_json_field "$existing_json" database)"
    existing_path="$(doctor_json_field "$existing_json" path)"
    existing_http="$(doctor_json_field "$existing_json" http_port)"
    existing_socket="$(doctor_json_field "$existing_json" socket_port)"
    doctor_err "Domain đã có trong Inventory: $existing_site"
    errors=$((errors+1))
  else
    doctor_ok "Domain chưa được Inventory sử dụng."
  fi

  conflicts="$(platform_nginx_conflict_files "$domain" 2>/dev/null || true)"
  if [[ -n "$conflicts" ]]; then
    doctor_err "Nginx server_name conflict:"
    printf '%s\n' "$conflicts" | sed 's/^/       /'
    errors=$((errors+1))
  else
    doctor_ok "Không có Nginx server_name conflict."
  fi

  if platform_ssl_exists "$domain"; then
    if platform_ssl_verify "$domain" >/dev/null 2>&1; then
      doctor_ok "SSL certificate đã tồn tại và hợp lệ."
    else
      doctor_warn "Có SSL artifact nhưng verify chưa đạt."
      warnings=$((warnings+1))
    fi
  else
    doctor_info "SSL chưa có; Provision/Restore có thể issue certificate sau khi Nginx hoạt động."
  fi

  if [[ -n "$existing_site" ]]; then
    echo
    echo "----- EXISTING SITE -----"
    echo "Site        : $existing_site"
    echo "Database    : ${existing_db:-N/A}"
    echo "Path        : ${existing_path:-N/A}"
    echo "HTTP port   : ${existing_http:-N/A}"
    echo "Socket port : ${existing_socket:-N/A}"
    doctor_backup_info "$existing_site"
  fi

  echo
  echo "----- TARGET IDENTITY -----"

  if [[ -n "$name" ]]; then
    owner="$(doctor_inventory_owner_by_field name "$name" 2>/dev/null || true)"
    if [[ -n "$owner" ]]; then
      doctor_err "Site name đã tồn tại trong Inventory: $owner"
      errors=$((errors+1))
    else
      doctor_ok "Site name khả dụng: $name"
    fi
    path="${path:-$(site_projects_root)/$(site_slugify "$name")}"
  fi

  if [[ -n "$path" ]]; then
    if [[ -e "$path" ]]; then
      doctor_err "Target path đã tồn tại: $path"
      errors=$((errors+1))
    else
      doctor_ok "Target path khả dụng: $path"
    fi
  else
    doctor_info "Không kiểm tra path vì chưa có --name hoặc --path."
  fi

  if [[ -n "$database" ]]; then
    owner="$(doctor_inventory_owner_by_field database "$database" 2>/dev/null || true)"
    if [[ -n "$owner" ]]; then
      doctor_err "Database đã thuộc Inventory site: $owner"
      errors=$((errors+1))
    else
      doctor_ok "Database chưa được Inventory sử dụng: $database"
    fi
  else
    doctor_info "Không kiểm tra database vì chưa có --database."
  fi

  echo
  echo "----- PLATFORM RUNTIME -----"

  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    doctor_ok "Docker daemon hoạt động."
  else
    doctor_err "Docker daemon không sẵn sàng."
    errors=$((errors+1))
  fi

  if docker compose version >/dev/null 2>&1; then
    doctor_ok "Docker Compose plugin hoạt động."
  else
    doctor_err "Docker Compose plugin không sẵn sàng."
    errors=$((errors+1))
  fi

  if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
    doctor_ok "Nginx configuration hợp lệ."
  else
    doctor_err "Nginx không sẵn sàng hoặc nginx -t lỗi."
    errors=$((errors+1))
  fi

  if command -v certbot >/dev/null 2>&1; then
    doctor_ok "Certbot available."
  else
    doctor_warn "Certbot không có; không thể tự issue Let's Encrypt SSL."
    warnings=$((warnings+1))
  fi

  echo
  echo "----- PORTS -----"

  if [[ "$http_port" == "auto" ]]; then
    http_candidate="$(doctor_find_free_port_value 8081)"
    doctor_ok "HTTP port khả dụng tiếp theo: $http_candidate"
  elif doctor_check_requested_port "HTTP port" "$http_port"; then
    http_candidate="$http_port"
  else
    errors=$((errors+1))
  fi

  if [[ "$socket_port" == "auto" ]]; then
    socket_candidate="$(doctor_find_free_port_value 6001)"
    doctor_ok "Socket port khả dụng tiếp theo: $socket_candidate"
  elif doctor_check_requested_port "Socket port" "$socket_port"; then
    socket_candidate="$socket_port"
  else
    errors=$((errors+1))
  fi

  echo
  echo "========================================================="
  echo "RESULT"
  echo "========================================================="

  if [[ "$errors" -eq 0 ]]; then
    echo "[READY] Domain đủ điều kiện cho Provision/Restore-as-new."
    [[ "$warnings" -gt 0 ]] && echo "[WARN] Có $warnings cảnh báo cần xem ở trên."
    echo "HTTP candidate   : ${http_candidate:-N/A}"
    echo "Socket candidate : ${socket_candidate:-N/A}"
    echo "========================================================="
    return 0
  fi

  echo "[NOT READY] Domain không thể dùng cho site mới."
  echo "Errors            : $errors"
  [[ "$warnings" -gt 0 ]] && echo "Warnings          : $warnings"

  if [[ -n "$existing_site" ]]; then
    echo
    echo "Existing site     : $existing_site"
    echo "Existing database : ${existing_db:-N/A}"
    echo "Backup command    : platform-v2 backup list $existing_site"
  fi

  echo "========================================================="
  return 1
}
