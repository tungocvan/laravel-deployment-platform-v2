#!/usr/bin/env bash

site_create_report() {
  python3 - "$@" <<'PY'
import json,sys
name,domain,path,repo,branch,http,socket,database=sys.argv[1:]
print(json.dumps({
  "status":"success",
  "strategy":"git-clone",
  "name":name,
  "domain":domain,
  "path":path,
  "repo":repo,
  "branch":branch,
  "http_port":int(http),
  "socket_port":int(socket),
  "database":database
},ensure_ascii=False,indent=2))
PY
}

site_create() {
  require_root
  require_command git
  require_command python3

  local name="" domain="" repo="" branch="main" project_path=""
  local http_port="auto" socket_port="auto"
  local ssl=1 no_build=0 dry_run=0 auto_yes=0
  local committed=0 nginx_created=0 arg

  for arg in "$@"; do
    case "$arg" in
      --name=*) name="${arg#*=}" ;;
      --domain=*) domain="${arg#*=}" ;;
      --repo=*) repo="${arg#*=}" ;;
      --branch=*) branch="${arg#*=}" ;;
      --path=*) project_path="${arg#*=}" ;;
      --http-port=*) http_port="${arg#*=}" ;;
      --socket-port=*) socket_port="${arg#*=}" ;;
      --no-ssl) ssl=0 ;;
      --no-build) no_build=1 ;;
      --dry-run) dry_run=1 ;;
      --yes) auto_yes=1 ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  [[ -n "$name" ]] || die "Thiếu --name"
  [[ -n "$domain" ]] || die "Thiếu --domain"
  [[ -n "$repo" ]] || die "Thiếu --repo"
  [[ -n "$branch" ]] || die "--branch không được rỗng"

  site_validate_domain "$domain" || die "Domain không hợp lệ: $domain"
  site_assert_name_available "$name"
  site_assert_domain_available "$domain"

  project_path="${project_path:-$(site_projects_root)/$(site_slugify "$name")}"
  [[ ! -e "$project_path" ]] || die "Path đã tồn tại: $project_path"

  http_port="$(site_choose_port "$http_port" "${START_HTTP_PORT:-8081}")"
  socket_port="$(site_choose_port "$socket_port" "${START_SOCKET_PORT:-6001}")"

  local db_name docker_identity
  db_name="db_$(site_slugify "$name" | tr '-' '_')"
  docker_identity="$(site_slugify "$name")"

  echo "========================================================="
  echo "CREATE SITE PLAN"
  echo "========================================================="
  echo "Name         : $name"
  echo "Domain       : $domain"
  echo "Repository   : $repo"
  echo "Branch       : $branch"
  echo "Path         : $project_path"
  echo "HTTP port    : $http_port"
  echo "Socket port  : $socket_port"
  echo "Database     : $db_name"
  echo "Docker name  : $docker_identity"
  echo "SSL          : $([[ "$ssl" -eq 1 ]] && echo YES || echo NO)"
  echo "Build        : $([[ "$no_build" -eq 1 ]] && echo NO || echo YES)"
  echo "========================================================="

  [[ "$dry_run" -eq 0 ]] || { echo "[DRY-RUN] Không thay đổi hệ thống."; return 0; }
  [[ "$auto_yes" -eq 1 ]] || site_confirm "Create Laravel site?" || die "Đã hủy."

  trap 'rc=$?; if [[ $rc -ne 0 && $committed -eq 0 ]]; then
          site_provision_cleanup_new_target "$project_path" "$domain" "$nginx_created"
        fi
        exit $rc' ERR

  site_step 1 "Validate identity và allocate resources"
  echo "[OK] Identity/resources validated"

  site_step 2 "Clone Git repository"
  platform_git_clone "$repo" "$project_path" "$branch"
  echo "[OK] Git HEAD: $(platform_git_commit_short "$project_path")"

  site_step 3 "Configure target environment"
  site_provision_configure_target \
    "$project_path" "$name" "$domain" "$db_name" \
    "$http_port" "$socket_port" 1

  site_step 4 "Prepare Docker runtime"
  site_provision_prepare_runtime "$name" "$project_path" "$no_build" 120

  site_step 5 "Finalize application runtime"
  site_provision_finalize_runtime "$project_path"

  site_step 6 "Provision Nginx"
  platform_nginx_ensure_proxy "$domain" "$http_port"
  nginx_created=1

  site_step 7 "Provision SSL"
  if [[ "$ssl" -eq 1 ]]; then
    if platform_ssl_exists "$domain"; then
      platform_ssl_verify "$domain"
      echo "[OK] SSL đã tồn tại: $domain"
    else
      platform_ssl_issue "$domain"
    fi
  else
    echo "[INFO] SSL skipped."
  fi

  site_step 8 "Health gate"
  site_provision_health "$project_path"

  site_step 9 "Inventory commit"
  site_provision_commit_inventory "$name" "$project_path"

  committed=1
  trap - ERR

  success "Create site thành công: $name"
  site_create_report "$name" "$domain" "$project_path" "$repo" "$branch" \
    "$http_port" "$socket_port" "$db_name"
}
