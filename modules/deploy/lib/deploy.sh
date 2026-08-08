#!/usr/bin/env bash

deploy_docker_platform_dir() {
  printf '%s' "${DOCKER_PLATFORM_DIR:-/opt/laravel-docker-platform}"
}

deploy_compose_wrapper() {
  printf '%s/scripts/compose.sh' "$(deploy_docker_platform_dir)"
}

deploy_preflight_script() {
  printf '%s/scripts/preflight.sh' "$(deploy_docker_platform_dir)"
}

deploy_slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

deploy_resolve_path() {
  local key="${1:-}"
  [[ -n "$key" ]] || die "Thiếu site hoặc project path."

  if [[ -d "$key" ]]; then
    readlink -f "$key"
    return
  fi

  local path
  path="$(inventory_get_field "$key" path 2>/dev/null || true)"
  [[ -n "$path" && -d "$path" ]] || die "Không tìm thấy project: $key"
  readlink -f "$path"
}

deploy_inventory_name_for_path() {
  local project_dir="$1"
  python3 - "$(inventory_file)" "$project_dir" <<'PY'
import json,sys,os
file,path=sys.argv[1:]
path=os.path.realpath(path)
with open(file,encoding="utf-8") as f:
    d=json.load(f)
for site in d.get("sites",[]):
    p=site.get("path")
    if p and os.path.realpath(p)==path:
        print(site.get("name",""))
        raise SystemExit(0)
print("")
PY
}

deploy_env_get() {
  local file="$1" key="$2"
  [[ -f "$file" ]] || return 0
  sed -n -E "s/^${key}=(.*)$/\1/p" "$file" | tail -n 1
}

deploy_env_set() {
  local file="$1" key="$2" value="$3" escaped
  escaped="$(printf '%s' "$value" | sed 's/[&|]/\\&/g')"
  touch "$file"

  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >> "$file"
  fi
}

deploy_resolve_identity() {
  local key="$1" project_dir="$2"
  local env_file="$project_dir/.docker-platform.env"
  local existing inventory_name identity

  existing="$(deploy_env_get "$env_file" COMPOSE_PROJECT_NAME || true)"
  inventory_name="$(deploy_inventory_name_for_path "$project_dir")"

  if [[ -n "$inventory_name" ]]; then
    identity="$(deploy_slugify "$inventory_name")"
  elif [[ -n "$existing" && "$existing" != "laravel-app" ]]; then
    identity="$(deploy_slugify "$existing")"
  elif [[ -n "$key" && ! -d "$key" ]]; then
    identity="$(deploy_slugify "$key")"
  else
    identity="$(deploy_slugify "$(basename "$project_dir")")"
  fi

  [[ -n "$identity" ]] || die "Không xác định được Docker project identity."

  # `laravel-app` is the template fallback and unsafe on this multi-site host.
  [[ "$identity" != "laravel-app" ]] || die \
    "COMPOSE_PROJECT_NAME=laravel-app không được phép cho managed multi-site deploy."

  printf '%s\n' "$identity"
}

deploy_ensure_identity_path() {
  local key="$1" project_dir="$2"
  local env_file="$project_dir/.docker-platform.env"
  local identity current

  [[ -f "$env_file" ]] || {
    if [[ -f "$project_dir/.docker-platform.env.example" ]]; then
      cp "$project_dir/.docker-platform.env.example" "$env_file"
    else
      touch "$env_file"
    fi
  }

  identity="$(deploy_resolve_identity "$key" "$project_dir")"
  current="$(deploy_env_get "$env_file" COMPOSE_PROJECT_NAME || true)"

  if [[ "$current" != "$identity" ]]; then
    deploy_env_set "$env_file" COMPOSE_PROJECT_NAME "$identity"
    echo "[INFO] Docker identity: ${current:-<unset>} -> $identity"
  else
    echo "[OK] Docker identity: $identity"
  fi

  printf '%s\n' "$identity"
}

deploy_compose() {
  local project_dir="$1"; shift
  local wrapper
  wrapper="$(deploy_compose_wrapper)"
  [[ -x "$wrapper" ]] || die "Không tìm thấy compose wrapper: $wrapper"
  PROJECT_DIR="$project_dir" "$wrapper" "$@"
}

deploy_preflight() {
  local project_dir="$1"
  local script
  script="$(deploy_preflight_script)"
  [[ -x "$script" ]] || die "Không tìm thấy preflight script: $script"
  PROJECT_DIR="$project_dir" "$script"
}

deploy_step() {
  printf '[DEPLOY %s] %s\n' "$1" "$2"
}

deploy_identity() {
  require_root
  local key="${1:-}"
  local project_dir identity env_file http socket

  project_dir="$(deploy_resolve_path "$key")"
  identity="$(deploy_ensure_identity_path "$key" "$project_dir" | tail -n 1)"
  env_file="$project_dir/.docker-platform.env"
  http="$(deploy_env_get "$env_file" HTTP_PORT || true)"
  socket="$(deploy_env_get "$env_file" SOCKET_PORT || true)"

  python3 - "$project_dir" "$identity" "$http" "$socket" <<'PY'
import json,sys
path,identity,http,socket=sys.argv[1:]
print(json.dumps({
  "path":path,
  "compose_project_name":identity,
  "http_port":int(http) if http.isdigit() else None,
  "socket_port":int(socket) if socket.isdigit() else None
},ensure_ascii=False,indent=2))
PY
}

deploy_wait_database() {
  local project_dir="$1" timeout="${2:-120}"
  local started now
  started="$(date +%s)"

  while true; do
    if deploy_compose "$project_dir" ps db 2>/dev/null | grep -Eq 'Up|healthy|running'; then
      if deploy_compose "$project_dir" exec -T app php -r '
        $h=getenv("DB_HOST") ?: "db";
        $p=(int)(getenv("DB_PORT") ?: 3306);
        $d=getenv("DB_DATABASE") ?: "";
        $u=getenv("DB_USERNAME") ?: "";
        $pw=getenv("DB_PASSWORD") ?: "";
        try {
          new PDO("mysql:host={$h};port={$p};dbname={$d}", $u, $pw, [PDO::ATTR_TIMEOUT=>2]);
          exit(0);
        } catch (Throwable $e) { exit(1); }
      ' >/dev/null 2>&1; then
        return 0
      fi
    fi

    now="$(date +%s)"
    if (( now - started >= timeout )); then
      die "Timeout chờ database (${timeout}s)."
    fi
    sleep 2
  done
}

deploy_prepare_path() {
  local key="$1" project_dir="$2" no_build="$3" timeout="$4"

  deploy_step "00/04" "Ensure Docker project identity"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null

  deploy_step "01/04" "Preflight"
  deploy_preflight "$project_dir"

  if [[ "$no_build" -eq 0 ]]; then
    deploy_step "02/04" "Docker build"
    deploy_compose "$project_dir" build
  else
    deploy_step "02/04" "Skip Docker build"
  fi

  deploy_step "03/04" "Docker up"
  deploy_compose "$project_dir" up -d

  deploy_step "04/04" "Wait database"
  deploy_wait_database "$project_dir" "$timeout"

  success "Deploy prepare hoàn tất: $project_dir"
}

deploy_prepare() {
  require_root
  local key="${1:-}"; shift || true
  local no_build=0 timeout=120 arg

  for arg in "$@"; do
    case "$arg" in
      --no-build) no_build=1 ;;
      --timeout=*) timeout="${arg#*=}" ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  [[ "$timeout" =~ ^[0-9]+$ ]] || die "--timeout phải là số."
  local project_dir
  project_dir="$(deploy_resolve_path "$key")"
  deploy_prepare_path "$key" "$project_dir" "$no_build" "$timeout"
}

deploy_migrate_path() {
  local project_dir="$1"
  deploy_step "MIGRATE" "Laravel migrate --force"
  deploy_compose "$project_dir" exec -T app php artisan migrate --force
}

deploy_migrate() {
  require_root
  local key="${1:-}" project_dir
  project_dir="$(deploy_resolve_path "$key")"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null
  deploy_migrate_path "$project_dir"
  success "Migration hoàn tất."
}

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
}

deploy_optimize() {
  require_root
  local key="${1:-}" project_dir
  project_dir="$(deploy_resolve_path "$key")"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null
  deploy_optimize_path "$project_dir"
  success "Laravel optimize hoàn tất."
}

deploy_health_path() {
  local project_dir="$1" errors=0

  for svc in db redis app web; do
    if deploy_compose "$project_dir" ps "$svc" 2>/dev/null | grep -Eq 'Up|healthy|running'; then
      echo "[OK] service $svc"
    else
      echo "[ERROR] service $svc"
      errors=$((errors+1))
    fi
  done

  if deploy_compose "$project_dir" exec -T app php artisan --version >/dev/null 2>&1; then
    echo "[OK] Laravel CLI"
  else
    echo "[ERROR] Laravel CLI"
    errors=$((errors+1))
  fi

  [[ "$errors" -eq 0 ]] || die "Deploy health phát hiện $errors lỗi."
}

deploy_health() {
  local key="${1:-}" project_dir
  project_dir="$(deploy_resolve_path "$key")"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null
  deploy_health_path "$project_dir"
  success "Deploy health OK."
}

deploy_status() {
  local key="${1:-}" project_dir
  project_dir="$(deploy_resolve_path "$key")"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null
  deploy_compose "$project_dir" ps
}

deploy_finalize_path() {
  local project_dir="$1"
  deploy_migrate_path "$project_dir"
  deploy_optimize_path "$project_dir"
  deploy_health_path "$project_dir"
}

deploy_run() {
  require_root

  local key="${1:-}"; shift || true
  local no_build=0 timeout=120 arg
  for arg in "$@"; do
    case "$arg" in
      --no-build) no_build=1 ;;
      --timeout=*) timeout="${arg#*=}" ;;
      *) die "Option không hợp lệ: $arg" ;;
    esac
  done

  [[ "$timeout" =~ ^[0-9]+$ ]] || die "--timeout phải là số."

  local project_dir
  project_dir="$(deploy_resolve_path "$key")"

  deploy_step "00/07" "Ensure Docker project identity"
  deploy_ensure_identity_path "$key" "$project_dir" >/dev/null

  deploy_step "01/07" "Preflight"
  deploy_preflight "$project_dir"

  if [[ "$no_build" -eq 0 ]]; then
    deploy_step "02/07" "Docker build"
    deploy_compose "$project_dir" build
  else
    deploy_step "02/07" "Skip Docker build"
  fi

  deploy_step "03/07" "Docker up"
  deploy_compose "$project_dir" up -d

  deploy_step "04/07" "Wait database"
  deploy_wait_database "$project_dir" "$timeout"

  deploy_step "05/07" "Laravel migrate"
  deploy_migrate_path "$project_dir"

  deploy_step "06/07" "Laravel optimize"
  deploy_optimize_path "$project_dir"

  deploy_step "07/07" "Health check"
  deploy_health_path "$project_dir"

  success "Deploy hoàn tất: $project_dir"
}


deploy_frontend_package_manager() {
  local project_dir="$1"
  if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
    printf 'pnpm'
  elif [[ -f "$project_dir/yarn.lock" ]]; then
    printf 'yarn'
  else
    printf 'npm'
  fi
}

deploy_frontend_is_vite() {
  local project_dir="$1"
  [[ -f "$project_dir/vite.config.js" || -f "$project_dir/vite.config.ts" ||
     -f "$project_dir/vite.config.mjs" || -f "$project_dir/vite.config.cjs" ]] && return 0
  [[ -f "$project_dir/package.json" ]] || return 1
  python3 - "$project_dir/package.json" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception:
    raise SystemExit(1)
deps={}
deps.update(d.get("dependencies") or {})
deps.update(d.get("devDependencies") or {})
raise SystemExit(0 if "vite" in deps else 1)
PY
}

deploy_frontend_has_script() {
  local project_dir="$1" script="$2"
  [[ -f "$project_dir/package.json" ]] || return 1
  python3 - "$project_dir/package.json" "$script" <<'PY'
import json,sys
try:d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception:raise SystemExit(1)
raise SystemExit(0 if sys.argv[2] in (d.get("scripts") or {}) else 1)
PY
}

deploy_frontend_scripts() {
  local key="${1:-}" project_dir
  project_dir="$(deploy_resolve_path "$key")"
  [[ -f "$project_dir/package.json" ]] || die "Project không có package.json: $project_dir"

  python3 - "$project_dir/package.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
for name,cmd in (d.get("scripts") or {}).items():
    print(f"{name}\t{cmd}")
PY
}

deploy_frontend_detect() {
  local key="${1:-}" project_dir pm owner docker_stage services
  project_dir="$(deploy_resolve_path "$key")"
  owner="$(stat -c '%U' "$project_dir")"
  pm="$(deploy_frontend_package_manager "$project_dir")"

  docker_stage=false
  services=""
  if deploy_frontend_has_docker_stage "$project_dir"; then
    docker_stage=true
    services="$(deploy_frontend_docker_services "$project_dir" 2>/dev/null || true)"
  fi

  python3 - "$project_dir" "$pm" "$owner" "$docker_stage" "$services" <<'PY'
import json,sys,pathlib,shutil
path=pathlib.Path(sys.argv[1]); pm=sys.argv[2]; owner=sys.argv[3]
docker_stage=sys.argv[4].lower()=="true"
docker_services=sys.argv[5].split() if sys.argv[5] else []
pkg=path/"package.json"
data={}
if pkg.exists():
    try:data=json.loads(pkg.read_text(encoding="utf-8"))
    except Exception:pass
deps={}
deps.update(data.get("dependencies") or {})
deps.update(data.get("devDependencies") or {})
vite=any((path/x).exists() for x in (
 "vite.config.js","vite.config.ts","vite.config.mjs","vite.config.cjs"
)) or "vite" in deps
print(json.dumps({
 "path":str(path),
 "laravel":(path/"artisan").exists(),
 "package_json":pkg.exists(),
 "node_modules":(path/"node_modules").exists(),
 "package_manager":pm,
 "package_manager_available":shutil.which(pm) is not None,
 "vite":vite,
 "build_script":"build" in (data.get("scripts") or {}),
 "scripts":data.get("scripts") or {},
 "project_owner":owner,
 "vite_manifest":str(path/"public/build/manifest.json"),
 "vite_manifest_exists":(path/"public/build/manifest.json").exists(),
 "frontend_strategy":"docker-multistage" if docker_stage else "host",
 "docker_frontend_stage":docker_stage,
 "docker_services":docker_services
},ensure_ascii=False,indent=2))
PY
}

deploy_frontend_run_owner() {
  local project_dir="$1"; shift
  local owner
  owner="$(stat -c '%U' "$project_dir")"
  [[ -n "$owner" ]] || die "Không xác định được project owner: $project_dir"

  if [[ "$owner" == "root" || "$(id -u)" -ne 0 ]]; then
    (cd "$project_dir" && "$@")
  else
    command -v sudo >/dev/null 2>&1 || die "Cần sudo để chạy frontend dưới user $owner."
    sudo -u "$owner" -H bash -lc '
      set -Eeuo pipefail
      cd "$1"
      shift
      exec "$@"
    ' bash "$project_dir" "$@"
  fi
}

deploy_frontend_require_manager() {
  local pm="$1"
  command -v "$pm" >/dev/null 2>&1 || die \
    "Không tìm thấy $pm trên host. Frontend build cần package manager tương ứng."
}

deploy_frontend_install() {
  require_root
  local key="${1:-}" project_dir pm
  project_dir="$(deploy_resolve_path "$key")"
  [[ -f "$project_dir/package.json" ]] || die "Project không có package.json: $project_dir"
  pm="$(deploy_frontend_package_manager "$project_dir")"
  deploy_frontend_require_manager "$pm"

  deploy_step "FRONTEND" "Install dependencies ($pm)"
  case "$pm" in
    npm)
      if [[ -f "$project_dir/package-lock.json" || -f "$project_dir/npm-shrinkwrap.json" ]]; then
        deploy_frontend_run_owner "$project_dir" npm ci
      else
        deploy_frontend_run_owner "$project_dir" npm install
      fi
      ;;
    pnpm)
      if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
        deploy_frontend_run_owner "$project_dir" pnpm install --frozen-lockfile
      else
        deploy_frontend_run_owner "$project_dir" pnpm install
      fi
      ;;
    yarn)
      if [[ -f "$project_dir/yarn.lock" ]]; then
        deploy_frontend_run_owner "$project_dir" yarn install --frozen-lockfile
      else
        deploy_frontend_run_owner "$project_dir" yarn install
      fi
      ;;
    *) die "Package manager không hỗ trợ: $pm" ;;
  esac
  success "Frontend dependencies OK: $project_dir"
}

deploy_frontend_build() {
  require_root
  local key="${1:-}" project_dir pm
  project_dir="$(deploy_resolve_path "$key")"

  if deploy_frontend_has_docker_stage "$project_dir"; then
    echo "[INFO] Frontend strategy: Docker multi-stage"
    echo "[INFO] Host Node/npm không được sử dụng."
    deploy_frontend_build_docker "$project_dir"
    return 0
  fi

  echo "[INFO] Frontend strategy: Host package manager fallback"
  [[ -f "$project_dir/package.json" ]] || die "Project không có package.json: $project_dir"
  deploy_frontend_has_script "$project_dir" build || die "package.json không có script 'build'."

  pm="$(deploy_frontend_package_manager "$project_dir")"
  deploy_frontend_require_manager "$pm"

  if [[ ! -d "$project_dir/node_modules" ]]; then
    echo "[INFO] node_modules chưa có; cài dependencies trước."
    deploy_frontend_install "$project_dir"
  fi

  deploy_step "FRONTEND" "Production build ($pm run build)"
  deploy_frontend_run_owner "$project_dir" "$pm" run build

  if deploy_frontend_is_vite "$project_dir"; then
    [[ -f "$project_dir/public/build/manifest.json" ]] || die \
      "Build command thành công nhưng thiếu Vite manifest: $project_dir/public/build/manifest.json"
    echo "[OK] Vite manifest: $project_dir/public/build/manifest.json"
  fi

  success "Frontend production build hoàn tất: $project_dir"
}


deploy_frontend_dockerfile() {
  local project_dir="$1"
  if [[ -f "$project_dir/Dockerfile" ]]; then
    printf '%s' "$project_dir/Dockerfile"
    return 0
  fi
  return 1
}

deploy_frontend_has_docker_stage() {
  local project_dir="$1" dockerfile
  dockerfile="$(deploy_frontend_dockerfile "$project_dir" 2>/dev/null || true)"
  [[ -n "$dockerfile" ]] || return 1
  grep -Eq '^[[:space:]]*FROM[[:space:]].+[[:space:]]+AS[[:space:]]+frontend-build([[:space:]]|$)' "$dockerfile"
}

deploy_frontend_docker_services() {
  local project_dir="$1"
  deploy_compose "$project_dir" config --format json |
    python3 -c '
import json,sys
d=json.load(sys.stdin)
services=d.get("services",{})
wanted=[]
for name in ("app","web"):
    s=services.get(name) or {}
    b=s.get("build")
    if isinstance(b,dict):
        dockerfile=str(b.get("dockerfile") or "Dockerfile")
        if dockerfile=="Dockerfile":
            wanted.append(name)
print(" ".join(wanted))
'
}

deploy_frontend_build_docker() {
  local project_dir="$1"
  local services
  services="$(deploy_frontend_docker_services "$project_dir")"
  [[ -n "$services" ]] || die "Không tìm thấy compose service app/web dùng Dockerfile frontend."

  # shellcheck disable=SC2206
  local service_arr=( $services )

  deploy_step "FRONTEND" "Docker multi-stage build (${service_arr[*]})"
  deploy_compose "$project_dir" build "${service_arr[@]}"

  deploy_step "FRONTEND" "Refresh frontend runtime (${service_arr[*]})"
  deploy_compose "$project_dir" up -d "${service_arr[@]}"

  deploy_step "FRONTEND" "Health"
  deploy_health "$project_dir"

  success "Docker frontend production build hoàn tất: $project_dir"
}
