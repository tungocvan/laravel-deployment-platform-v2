#!/usr/bin/env bash

# Runtime safety layer for deploy.sh.
# Source this file after deploy.sh (and readiness.sh when used) so these
# implementations intentionally strengthen the existing deploy contract.

deploy_runtime_service_exists() {
  local project_dir="$1" service="$2"
  deploy_compose "$project_dir" config --services 2>/dev/null | grep -Fxq "$service"
}

deploy_wait_service_ready_path() {
  local project_dir="$1" service="$2" timeout="${3:-120}"
  local started now output

  deploy_runtime_service_exists "$project_dir" "$service" || return 0
  started="$(date +%s)"

  while true; do
    output="$(deploy_compose "$project_dir" ps "$service" 2>/dev/null || true)"
    if grep -Eq 'healthy|running|Up' <<<"$output" && ! grep -Eq 'unhealthy|Restarting|Exited|starting' <<<"$output"; then
      return 0
    fi

    now="$(date +%s)"
    if (( now - started >= timeout )); then
      die "Timeout chờ service $service sẵn sàng (${timeout}s)."
    fi
    sleep 2
  done
}

deploy_restart_php_runtime_path() {
  local project_dir="$1" timeout="${2:-120}"
  local service
  local -a services=()

  for service in app queue queue-admission-documents scheduler; do
    if deploy_runtime_service_exists "$project_dir" "$service"; then
      services+=("$service")
    fi
  done

  [[ " ${services[*]} " == *" app "* ]] || die "Compose project không có service app."

  echo "[INFO] Restart PHP runtime để nạp config/opcache mới: ${services[*]}"
  deploy_compose "$project_dir" restart "${services[@]}"

  for service in "${services[@]}"; do
    deploy_wait_service_ready_path "$project_dir" "$service" "$timeout"
    echo "[OK] runtime $service"
  done
}

deploy_resolve_http_port_path() {
  local project_dir="$1" port=""

  port="$(deploy_env_get "$project_dir/.docker-platform.env" HTTP_PORT || true)"
  [[ "$port" =~ ^[0-9]+$ ]] || port="$(deploy_env_get "$project_dir/.env" HTTP_PORT || true)"

  if [[ ! "$port" =~ ^[0-9]+$ ]]; then
    port="$(deploy_compose "$project_dir" port web 8080 2>/dev/null | tail -n 1 | sed -E 's/.*:([0-9]+)$/\1/' || true)"
  fi

  [[ "$port" =~ ^[0-9]+$ ]] || die "Không xác định được HTTP port để verify application."
  printf '%s\n' "$port"
}

deploy_verify_application_http_path() {
  local project_dir="$1" timeout="${2:-60}"
  local port started now code url

  command -v curl >/dev/null 2>&1 || die "Thiếu curl để verify application HTTP."

  port="$(deploy_resolve_http_port_path "$project_dir")"
  url="http://127.0.0.1:${port}/"
  started="$(date +%s)"

  while true; do
    code="$(curl -sS -o /dev/null --max-time 10 -w '%{http_code}' "$url" 2>/dev/null || true)"
    if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
      echo "[OK] Application HTTP: $code ($url)"
      return 0
    fi

    now="$(date +%s)"
    if (( now - started >= timeout )); then
      echo "[ERROR] Application HTTP: ${code:-000} ($url)"
      die "Application HTTP verification failed; deploy không được đánh dấu thành công."
    fi
    sleep 2
  done
}

# Override deploy.sh: rebuild Laravel caches, then restart all long-lived PHP
# runtimes so PHP-FPM/workers cannot keep stale config/opcache in memory.
deploy_optimize_path() {
  local project_dir="$1"

  deploy_step "OPTIMIZE" "Clear Laravel caches safely"
  deploy_compose "$project_dir" exec -T app \
    env CACHE_STORE=array CACHE_DRIVER=array \
    php artisan optimize:clear

  deploy_step "OPTIMIZE" "Cache production config/routes/views"
  deploy_compose "$project_dir" exec -T app php artisan config:cache

  if ! deploy_compose "$project_dir" exec -T app php artisan route:cache; then
    warn "route:cache thất bại; tiếp tục deploy."
  fi

  if ! deploy_compose "$project_dir" exec -T app php artisan view:cache; then
    warn "view:cache thất bại; tiếp tục deploy."
  fi

  deploy_step "OPTIMIZE" "Restart PHP runtime after cache refresh"
  deploy_restart_php_runtime_path "$project_dir" "${PLATFORM_DEPLOY_RUNTIME_TIMEOUT:-120}"
}

# Override deploy.sh: a healthy php-fpm process is insufficient. Laravel must
# bootstrap successfully and a real request through the local web port must
# return 2xx/3xx before deploy can succeed.
deploy_health_path() {
  local project_dir="$1" errors=0 service

  for service in db redis app web; do
    if deploy_compose "$project_dir" ps "$service" 2>/dev/null | grep -Eq 'healthy|running|Up'; then
      echo "[OK] service $service"
    else
      echo "[ERROR] service $service"
      errors=$((errors+1))
    fi
  done

  for service in queue queue-admission-documents scheduler; do
    deploy_runtime_service_exists "$project_dir" "$service" || continue
    if deploy_compose "$project_dir" ps "$service" 2>/dev/null | grep -Eq 'healthy|running|Up'; then
      echo "[OK] worker $service"
    else
      echo "[ERROR] worker $service"
      errors=$((errors+1))
    fi
  done

  if deploy_compose "$project_dir" exec -T app php artisan about --no-ansi >/dev/null 2>&1; then
    echo "[OK] Laravel boot"
  else
    echo "[ERROR] Laravel boot"
    errors=$((errors+1))
  fi

  [[ "$errors" -eq 0 ]] || die "Deploy health phát hiện $errors lỗi trước HTTP verification."

  deploy_verify_application_http_path "$project_dir" "${PLATFORM_DEPLOY_HTTP_TIMEOUT:-60}"
}
