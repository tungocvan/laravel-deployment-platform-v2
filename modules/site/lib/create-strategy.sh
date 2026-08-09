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
    docker compose --env-file .docker-platform.env -f "$compose_file" "$@"
  )
}

site_create_repository_validate_contract() {
  local project_path="$1" dockerfile="$2" compose_file="$3"
  [[ -f "$project_path/$dockerfile" ]] || die "Thiếu Dockerfile repository: $dockerfile"
  [[ -f "$project_path/$compose_file" ]] || die "Thiếu Compose file repository: $compose_file"
  site_create_repository_compose "$project_path" "$compose_file" config >/dev/null

  local config
  config="$(site_create_repository_compose "$project_path" "$compose_file" config --services)"
  for svc in app web db; do
    grep -Fxq "$svc" <<<"$config" || die "Repository Compose thiếu service bắt buộc: $svc"
  done
}

site_create_repository_prepare() {
  local project_path="$1" compose_file="$2" timeout="${3:-120}"
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

site_create() {
  require_root
  require_command git
  require_command python3

  local name="" domain="" repo="" branch="main" project_path=""
  local http_port="auto" socket_port="auto" docker_strategy="platform"
  local dockerfile="Dockerfile" compose_file="compose.yaml" ssl=1 dry_run=0 auto_yes=0 timeout=120
  local resolved_strategy="" db_name="" committed=0 nginx_created=0 cloned=0

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
  site_assert_domain_available "$domain"
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

  if [[ "$dry_run" -eq 1 ]]; then
    echo "[DRY-RUN] Strategy requested: $docker_strategy; repository content chưa được clone nên auto detection chưa mutate hệ thống."
    echo "[DRY-RUN] Không thay đổi hệ thống."
    return 0
  fi
  [[ "$auto_yes" -eq 1 ]] || site_confirm "Create Laravel site?" || die "Đã hủy."

  trap 'rc=$?; if [[ $rc -ne 0 && $committed -eq 0 ]]; then
          if [[ "$resolved_strategy" == "repository" && -d "$project_path" ]]; then
            site_create_repository_compose "$project_path" "$compose_file" down -v --remove-orphans >/dev/null 2>&1 || true
          fi
          site_provision_cleanup_new_target "$project_path" "$domain" "$nginx_created"
        fi
        exit $rc' ERR

  platform_git_clone "$repo" "$project_path" "$branch"
  cloned=1
  site_create_validate_laravel "$project_path"
  resolved_strategy="$(site_create_resolve_strategy "$docker_strategy" "$project_path" "$dockerfile" "$compose_file")"
  echo "[OK] Runtime strategy resolved: $resolved_strategy"

  site_provision_configure_target "$project_path" "$name" "$domain" "$db_name" "$http_port" "$socket_port" 1

  if [[ "$resolved_strategy" == "repository" ]]; then
    site_create_repository_validate_contract "$project_path" "$dockerfile" "$compose_file"
    site_create_repository_prepare "$project_path" "$compose_file" "$timeout"
    site_create_repository_finalize "$project_path" "$compose_file"
    site_create_repository_health "$project_path" "$compose_file"
  else
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
