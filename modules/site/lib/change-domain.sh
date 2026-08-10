#!/usr/bin/env bash

site_change_domain_record_inventory() {
  local key="$1" old_domain="$2" new_domain="$3" ssl_status="$4"
  inventory_init
  python3 - "$(inventory_file)" "$key" "$old_domain" "$new_domain" "$ssl_status" <<'PY'
import datetime,json,os,sys
path,key,old_domain,new_domain,ssl_status=sys.argv[1:]
with open(path,encoding="utf-8") as f:d=json.load(f)
site=None
for item in d.get("sites",[]):
    if key in (str(item.get("name","")),str(item.get("domain","")),str(item.get("path",""))):
        site=item; break
if site is None: raise SystemExit("site not found")
site["previous_domain"]=old_domain
site["domain"]=new_domain
site["ssl_status"]=ssl_status
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
site["last_domain_changed_at"]=now
site["last_synced_at"]=now
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as f:
    json.dump(d,f,ensure_ascii=False,indent=2); f.write("\n")
os.replace(tmp,path)
PY
}

site_change_domain_refresh_app() {
  local key="$1" project_path="$2" strategy="$3"
  case "$strategy" in
    repository)
      local compose_file
      compose_file="$(inventory_get_field "$key" compose_file 2>/dev/null || true)"
      compose_file="${compose_file:-compose.yaml}"
      site_create_repository_compose "$project_path" "$compose_file" exec -T app \
        env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
      site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan config:cache
      site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan route:cache \
        || warn "route:cache thất bại; tiếp tục."
      site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan view:cache \
        || warn "view:cache thất bại; tiếp tục."
      site_create_repository_compose "$project_path" "$compose_file" restart app queue scheduler 2>/dev/null \
        || site_create_repository_compose "$project_path" "$compose_file" restart app
      site_create_repository_health "$project_path" "$compose_file"
      ;;
    platform|"")
      deploy_optimize_path "$project_path"
      deploy_compose "$project_path" restart app queue scheduler 2>/dev/null \
        || deploy_compose "$project_path" restart app
      deploy_health_path "$project_path"
      ;;
    *) die "Runtime strategy không hỗ trợ change-domain: $strategy" ;;
  esac
}

site_change_domain_gate() {
  local domain="$1" use_ssl="$2" replace_domain_config="$3" rc=0
  site_domain_preflight "$domain" || rc=$?
  case "$rc" in
    0) return 0 ;;
    10)
      [[ "$replace_domain_config" -eq 1 ]] || die "Domain mới có Nginx managed config cũ. Dùng --replace-domain-config sau khi xác nhận."
      warn "Sẽ làm mới Nginx managed config hiện có: $domain"
      ;;
    11)
      [[ "$use_ssl" -eq 0 ]] || die "DNS domain mới chưa trỏ đúng VPS; không đủ điều kiện SSL. Dùng --no-ssl hoặc cập nhật DNS."
      warn "DNS chưa trỏ đúng VPS; change-domain sẽ chạy không SSL."
      ;;
    12)
      [[ "$replace_domain_config" -eq 1 ]] || die "Domain mới có Nginx managed config cũ. Dùng --replace-domain-config sau khi xác nhận."
      [[ "$use_ssl" -eq 0 ]] || die "DNS domain mới chưa trỏ đúng VPS; không đủ điều kiện SSL."
      warn "Sẽ làm mới Nginx config và tiếp tục không SSL."
      ;;
    21) die "Domain mới đang thuộc managed site khác trong Inventory." ;;
    22) die "Domain mới đang nằm trong Nginx config không do Platform quản lý; từ chối ghi đè." ;;
    *) die "Domain preflight thất bại: $domain (exit=$rc)" ;;
  esac
}

site_change_domain() {
  require_root
  require_command python3
  require_command nginx

  local key="${1:-}"; shift || true
  local new_domain="" use_ssl=1 dry_run=0 auto_yes=0 replace_domain_config=0
  local arg
  [[ -n "$key" ]] || die "USAGE: platform site change-domain <site> --domain=<new-domain> [--dry-run] [--yes] [--no-ssl]"

  for arg in "$@"; do
    case "$arg" in
      --domain=*) new_domain="${arg#*=}" ;;
      --no-ssl) use_ssl=0 ;;
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      --replace-domain-config) replace_domain_config=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done
  [[ -n "$new_domain" ]] || die "Thiếu --domain=<new-domain>"
  platform_nginx_validate_domain "$new_domain"
  inventory_find_json "$key" >/dev/null 2>&1 || die "Không tìm thấy managed site: $key"

  local name old_domain project_path http_port strategy env_file old_app_url new_app_url ssl_status
  name="$(inventory_get_field "$key" name)"
  old_domain="$(inventory_get_field "$key" domain)"
  project_path="$(inventory_get_field "$key" path)"
  http_port="$(inventory_get_field "$key" http_port)"
  strategy="$(inventory_get_field "$key" runtime_strategy 2>/dev/null || true)"
  strategy="${strategy:-platform}"
  env_file="$project_path/.env"

  [[ "$new_domain" != "$old_domain" ]] || { success "Domain không thay đổi: $new_domain"; return 0; }
  [[ -d "$project_path" ]] || die "Project path không tồn tại: $project_path"
  [[ -f "$env_file" ]] || die "Không tìm thấy .env: $env_file"

  site_change_domain_gate "$new_domain" "$use_ssl" "$replace_domain_config"

  old_app_url="$(sed -n -E 's/^APP_URL=(.*)$/\1/p' "$env_file" | tail -n1)"
  if [[ "$use_ssl" -eq 1 ]]; then new_app_url="https://$new_domain"; else new_app_url="http://$new_domain"; fi

  echo "Site        : $name"
  echo "Old domain  : $old_domain"
  echo "New domain  : $new_domain"
  echo "APP_URL     : $new_app_url"
  echo "Path        : $project_path"
  echo "HTTP port   : $http_port"
  echo "Strategy    : $strategy"
  echo "SSL         : $use_ssl"
  echo "Keep data   : database/storage/path unchanged"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[DRY-RUN] Sẽ tạo Nginx domain mới, cấp SSL (nếu bật), đổi APP_URL, refresh Laravel, cập nhật Inventory, rồi remove Nginx domain cũ."
    echo "[DRY-RUN] Certificate domain cũ được giữ lại; không xóa tự động."
    return 0
  fi

  [[ "$auto_yes" -eq 1 ]] || site_confirm "Đổi domain $old_domain -> $new_domain?" || die "Đã hủy."

  local new_nginx_created=0 app_url_changed=0 inventory_changed=0
  trap 'rc=$?; if [[ $rc -ne 0 ]]; then
          warn "Change-domain thất bại; đang giữ/khôi phục domain cũ."
          if [[ $inventory_changed -eq 1 ]]; then site_change_domain_record_inventory "$name" "$new_domain" "$old_domain" "active" >/dev/null 2>&1 || true; fi
          if [[ $app_url_changed -eq 1 ]]; then
            site_provision_set_env_value "$env_file" APP_URL "$old_app_url" >/dev/null 2>&1 || true
            site_change_domain_refresh_app "$name" "$project_path" "$strategy" >/dev/null 2>&1 || true
          fi
          if [[ $new_nginx_created -eq 1 ]]; then platform_nginx_remove "$new_domain" >/dev/null 2>&1 || true; fi
          warn "Domain cũ vẫn được ưu tiên giữ hoạt động: $old_domain"
        fi
        exit $rc' ERR

  platform_nginx_ensure_proxy "$new_domain" "$http_port"
  new_nginx_created=1

  if [[ "$use_ssl" -eq 1 ]]; then
    if platform_ssl_exists "$new_domain"; then
      platform_ssl_verify "$new_domain"
    else
      platform_ssl_issue "$new_domain"
    fi
    ssl_status="active"
  else
    ssl_status="skipped"
  fi

  site_provision_set_env_value "$env_file" APP_URL "$new_app_url"
  app_url_changed=1
  site_change_domain_refresh_app "$name" "$project_path" "$strategy"

  site_change_domain_record_inventory "$name" "$old_domain" "$new_domain" "$ssl_status"
  inventory_changed=1

  platform_nginx_remove "$old_domain"
  trap - ERR

  success "Đổi domain thành công: $old_domain -> $new_domain"
  echo "[INFO] Certificate cũ (nếu có) được giữ lại để rollback thủ công khi cần."
}
