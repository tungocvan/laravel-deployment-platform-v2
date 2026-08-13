#!/usr/bin/env bash

site_create_resolve_strategy() {
  local requested="${1:-platform}" project_path="${2:-}" dockerfile="${3:-Dockerfile}" compose_file="${4:-compose.yaml}"
  case "$requested" in
    platform) printf 'platform\n' ;;
    repository)
      [[ -n "$project_path" && -f "$project_path/$dockerfile" ]] || die "Repository strategy thiếu Dockerfile: $dockerfile"
      [[ -f "$project_path/$compose_file" ]] || die "Repository strategy thiếu Compose file: $compose_file"
      printf 'repository\n'
      ;;
    auto)
      if [[ -n "$project_path" && -f "$project_path/$dockerfile" && -f "$project_path/$compose_file" ]]; then
        printf 'repository\n'
      else
        printf 'platform\n'
      fi
      ;;
    *) die "--docker phải là platform, repository hoặc auto" ;;
  esac
}

site_create_validate_laravel() {
  local project_path="$1"
  [[ -f "$project_path/artisan" ]] || die "Repository không phải Laravel project: thiếu artisan"
  [[ -f "$project_path/composer.json" ]] || die "Repository không phải Laravel project: thiếu composer.json"
}

site_create_repository_compose() {
  local project_path="$1" compose_file="$2"; shift 2
  require_command docker
  (
    cd "$project_path"
    docker compose --env-file .env --env-file .docker-platform.env -f "$compose_file" "$@"
  )
}

site_create_repository_prepare_env() {
  local project_path="$1" name="$2" domain="$3" database="$4" http_port="$5" socket_port="$6"

  if [[ ! -f "$project_path/.env" && -f "$project_path/.env.docker.example" ]]; then
    cp "$project_path/.env.docker.example" "$project_path/.env"
  fi

  site_provision_configure_target \
    "$project_path" "$name" "$domain" "$database" "$http_port" "$socket_port" 1

  require_command openssl
  local db_password root_password redis_password
  db_password="$(openssl rand -hex 24)"
  root_password="$(openssl rand -hex 24)"
  redis_password="$(openssl rand -hex 24)"

  site_provision_set_env_value "$project_path/.env" APP_ENV production
  site_provision_set_env_value "$project_path/.env" APP_DEBUG false
  site_provision_set_env_value "$project_path/.env" DB_HOST db
  site_provision_set_env_value "$project_path/.env" DB_PORT 3306
  site_provision_set_env_value "$project_path/.env" DB_USERNAME laravel
  site_provision_set_env_value "$project_path/.env" DB_PASSWORD "$db_password"
  site_provision_set_env_value "$project_path/.env" MARIADB_ROOT_PASSWORD "$root_password"
  site_provision_set_env_value "$project_path/.env" CACHE_STORE redis
  site_provision_set_env_value "$project_path/.env" SESSION_DRIVER redis
  site_provision_set_env_value "$project_path/.env" QUEUE_CONNECTION redis
  site_provision_set_env_value "$project_path/.env" REDIS_HOST redis
  site_provision_set_env_value "$project_path/.env" REDIS_PASSWORD "$redis_password"
  site_provision_set_env_value "$project_path/.env" REDIS_PORT 6379
  site_provision_set_env_value "$project_path/.env" NODEJS_SERVER_URL http://socket:6001
  site_provision_set_env_value "$project_path/.env" NODEJS_SERVER_PORT 6001
}

site_create_repository_validate_contract() {
  local project_path="$1" dockerfile="$2" compose_file="$3"
  [[ -f "$project_path/$dockerfile" ]] || die "Thiếu Dockerfile repository: $dockerfile"
  [[ -f "$project_path/$compose_file" ]] || die "Thiếu Compose file repository: $compose_file"

  local config services
  config="$(site_create_repository_compose "$project_path" "$compose_file" config)"
  services="$(site_create_repository_compose "$project_path" "$compose_file" config --services)"

  for svc in app web db; do
    grep -Fxq "$svc" <<<"$services" || die "Repository Compose thiếu service bắt buộc: $svc"
  done

  python3 - "$dockerfile" "$config" <<'PY' || die "Repository Compose service app không build từ Dockerfile đã chọn: $dockerfile"
import re,sys
wanted,text=sys.argv[1:]
lines=text.splitlines()
in_app=False
in_build=False
build_seen=False
explicit=None
for line in lines:
    if re.match(r'^  app:\s*$', line):
        in_app=True
        continue
    if in_app and line and not line.startswith('    '):
        break
    if not in_app:
        continue
    if re.match(r'^    build:\s*$', line):
        in_build=True
        build_seen=True
        continue
    if in_build and line and not line.startswith('      '):
        in_build=False
    if in_build:
        m=re.match(r'^      dockerfile:\s*["\']?([^"\']+)["\']?\s*$', line)
        if m:
            explicit=m.group(1)
            break
ok = build_seen and ((explicit == wanted) if explicit else wanted == 'Dockerfile')
raise SystemExit(0 if ok else 1)
PY
}

site_create_repository_prepare() {
  local project_path="$1" compose_file="$2" http_port="$3" timeout="${4:-120}"
  site_create_repository_compose "$project_path" "$compose_file" build
  site_create_repository_compose "$project_path" "$compose_file" up -d

  local started now
  started="$(date +%s)"
  while true; do
    if site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan --version >/dev/null 2>&1; then
      break
    fi
    now="$(date +%s)"
    (( now - started < timeout )) || die "Timeout chờ repository runtime (${timeout}s)."
    sleep 2
  done

  local published
  published="$(site_create_repository_compose "$project_path" "$compose_file" port web 8080 2>/dev/null | tail -n1 || true)"
  [[ -n "$published" ]] || die "Repository Compose phải publish service web port 8080"
  [[ "${published##*:}" == "$http_port" ]] || die "Repository web port không khớp HTTP_PORT=$http_port: $published"
}

site_create_repository_finalize() {
  local project_path="$1" compose_file="$2"
  site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan migrate --force
  site_create_repository_compose "$project_path" "$compose_file" exec -T app env CACHE_STORE=array CACHE_DRIVER=array php artisan optimize:clear
  site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan config:cache
  site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan route:cache || warn "route:cache thất bại; tiếp tục."
  site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan view:cache || warn "view:cache thất bại; tiếp tục."
}

site_create_repository_health() {
  local project_path="$1" compose_file="$2" errors=0
  for svc in app web db; do
    site_create_repository_compose "$project_path" "$compose_file" ps "$svc" 2>/dev/null | grep -Eq 'Up|healthy|running' || errors=$((errors+1))
  done
  site_create_repository_compose "$project_path" "$compose_file" exec -T app php artisan --version >/dev/null 2>&1 || errors=$((errors+1))
  [[ "$errors" -eq 0 ]] || die "Repository runtime health phát hiện $errors lỗi."
}

site_create_repository_cleanup() {
  local project_path="$1" compose_file="$2"
  [[ -d "$project_path" ]] || return 0
  site_create_repository_compose "$project_path" "$compose_file" down -v --remove-orphans >/dev/null 2>&1 || true
}

site_create_domain_gate() {
  local domain="$1" ssl="$2" replace_domain_config="$3" rc=0
  site_domain_preflight "$domain" || rc=$?

  case "$rc" in
    0) return 0 ;;
    10)
      [[ "$replace_domain_config" -eq 1 ]] || die "Domain có Nginx managed config cũ. Dùng --replace-domain-config sau khi xác nhận."
      warn "Sẽ làm mới Nginx managed config hiện có: $domain"
      ;;
    11)
      [[ "$ssl" -eq 0 ]] || die "DNS chưa trỏ đúng VPS; không đủ điều kiện cấp SSL. Dùng --no-ssl hoặc cập nhật DNS."
      warn "DNS chưa trỏ đúng VPS; tiếp tục create không SSL."
      ;;
    12)
      [[ "$replace_domain_config" -eq 1 ]] || die "Domain có Nginx managed config cũ. Dùng --replace-domain-config sau khi xác nhận."
      [[ "$ssl" -eq 0 ]] || die "DNS chưa trỏ đúng VPS; không đủ điều kiện cấp SSL."
      warn "Sẽ làm mới Nginx config và tiếp tục không SSL."
      ;;
    21) die "Domain đang thuộc một managed site khác trong Inventory; archive/purge site cũ trước." ;;
    22) die "Domain đang nằm trong Nginx config không do Platform quản lý; từ chối ghi đè." ;;
    *) die "Domain preflight thất bại: $domain (exit=$rc)" ;;
  esac
}

site_create() {
  require_root
  require_command git
  require_command python3

  local name="" domain="" repo="" branch="main" project_path=""
  local http_port="auto" socket_port="auto" docker_strategy="platform"
  local dockerfile="Dockerfile" compose_file="compose.yaml" ssl=1 dry_run=0 auto_yes=0 timeout=120
  local replace_domain_config=0 resolved_strategy="" db_name="" committed=0 nginx_created=0 keep_failed=0

  for arg in "$@"; do
    case "$arg" in
      --name=*) name="${arg#*=}" ;;
      --domain=*) domain="${arg#*=}" ;;
      --repo=*) repo="${arg#*=}" ;;
      --branch=*) branch="${arg#*=}" ;;
      --path=*) project_path="${arg#*=}" ;;
      --http-port=*) http_port="${arg#*=}" ;;
      --socket-port=*) socket_port="${arg#*=}" ;;
      --docker=*) docker_strategy="${arg#*=}" ;;
      --dockerfile=*) dockerfile="${arg#*=}" ;;
      --compose-file=*) compose_file="${arg#*=}" ;;
      --timeout=*) timeout="${arg#*=}" ;;
      --replace-domain-config) replace_domain_config=1 ;;
      --keep-failed) keep_failed=1 ;;
      --no-ssl) ssl=0 ;;
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  [[ -n "$name" && -n "$domain" && -n "$repo" ]] || die "Thiếu --name, --domain hoặc --repo"
  [[ "$timeout" =~ ^[0-9]+$ ]] || die "--timeout phải là số"
  case "$docker_strategy" in platform|repository|auto) ;; *) die "--docker phải là platform, repository hoặc auto" ;; esac

  platform_nginx_validate_domain "$domain"
  site_assert_name_available "$name"
  site_create_domain_gate "$domain" "$ssl" "$replace_domain_config"

  project_path="${project_path:-$(site_projects_root)/$(site_slugify "$name")}"
  [[ ! -e "$project_path" ]] || die "Path đã tồn tại: $project_path"
  http_port="$(site_choose_port "$http_port" 8081)"
  socket_port="$(site_choose_port "$socket_port" 6001)"
  db_name="db_$(site_slugify "$name" | tr '-' '_')"

  echo "Strategy    : $docker_strategy"
  echo "Name        : $name"
  echo "Domain      : $domain"
  echo "Repository  : $repo"
  echo "Branch      : $branch"
  echo "Path        : $project_path"
  echo "HTTP port   : $http_port"
  echo "Socket port : $socket_port"
  echo "Database    : $db_name"
  echo "Dockerfile  : $dockerfile"
  echo "Compose     : $compose_file"
  echo "SSL         : $ssl"
  echo "Keep failed : $keep_failed"
  echo "Replace Nginx managed config: $replace_domain_config"

  if [[ "$dry_run" -eq 1 ]]; then
    if [[ "$docker_strategy" == "auto" ]]; then
      echo "[DRY-RUN] Auto strategy sẽ được xác định sau khi clone repository: Dockerfile + Compose => repository, ngược lại => platform."
    else
      echo "[DRY-RUN] Runtime strategy: $docker_strategy"
    fi
    [[ "$keep_failed" -eq 1 ]] && echo "[DRY-RUN] Debug mode: nếu create thật thất bại sẽ giữ project/container để inspect."
    echo "[DRY-RUN] Không clone/build/start hoặc thay đổi Inventory."
    return 0
  fi
  [[ "$auto_yes" -eq 1 ]] || site_confirm "Create Laravel site?" || die "Đã hủy."

  trap 'rc=$?; if [[ $rc -ne 0 && $committed -eq 0 ]]; then
          if [[ "$keep_failed" -eq 1 ]]; then
            echo "[DEBUG] Create thất bại; --keep-failed đang bật nên KHÔNG cleanup runtime." >&2
            echo "[DEBUG] Project giữ lại: $project_path" >&2
            echo "[DEBUG] Strategy: ${resolved_strategy:-unresolved}" >&2
            echo "[DEBUG] Inventory chưa commit." >&2
          elif [[ "$resolved_strategy" == "repository" ]]; then
            site_create_repository_cleanup "$project_path" "$compose_file"
            [[ "$nginx_created" -eq 1 ]] && { platform_nginx_remove "$domain" >/dev/null 2>&1 || true; platform_ssl_remove "$domain" >/dev/null 2>&1 || true; }
            [[ -d "$project_path" ]] && rm -rf "$project_path" || true
          else
            site_provision_cleanup_new_target "$project_path" "$domain" "$nginx_created"
          fi
        fi
        exit $rc' ERR

  platform_git_clone "$repo" "$project_path" "$branch"
  site_create_validate_laravel "$project_path"
  resolved_strategy="$(site_create_resolve_strategy "$docker_strategy" "$project_path" "$dockerfile" "$compose_file")"
  echo "[OK] Runtime strategy resolved: $resolved_strategy"

  if [[ "$resolved_strategy" == "repository" ]]; then
    site_create_repository_prepare_env "$project_path" "$name" "$domain" "$db_name" "$http_port" "$socket_port"
    site_create_repository_validate_contract "$project_path" "$dockerfile" "$compose_file"
    site_create_repository_prepare "$project_path" "$compose_file" "$http_port" "$timeout"
    site_create_repository_finalize "$project_path" "$compose_file"
    site_create_repository_health "$project_path" "$compose_file"
  else
    site_provision_configure_target "$project_path" "$name" "$domain" "$db_name" "$http_port" "$socket_port" 1
    site_provision_prepare_runtime "$name" "$project_path" 0 "$timeout"
    site_provision_finalize_runtime "$project_path"
  fi

  platform_nginx_ensure_proxy "$domain" "$http_port"
  nginx_created=1
  if [[ "$ssl" -eq 1 ]]; then
    platform_ssl_exists "$domain" && platform_ssl_verify "$domain" || platform_ssl_issue "$domain"
  fi

  if [[ "$resolved_strategy" == "repository" ]]; then
    site_create_repository_health "$project_path" "$compose_file"
  else
    site_provision_health "$project_path"
  fi

  site_provision_commit_inventory "$name" "$project_path"
  inventory_set_runtime_strategy "$name" "$resolved_strategy" "$dockerfile" "$compose_file"
  committed=1
  trap - ERR
  success "Create site thành công: $name ($resolved_strategy)"
}
