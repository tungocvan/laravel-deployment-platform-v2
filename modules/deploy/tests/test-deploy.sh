#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}"
F="$ROOT/modules/deploy/lib/deploy.sh"
R="$ROOT/modules/deploy/lib/runtime-health.sh"
S="$ROOT/modules/deploy/lib/storage.sh"

for fn in \
  deploy_resolve_path deploy_compose deploy_prepare deploy_migrate \
  deploy_optimize deploy_health deploy_status \
  deploy_frontend_detect deploy_frontend_scripts \
  deploy_frontend_install deploy_frontend_build \
  deploy_frontend_package_manager deploy_frontend_run_owner
do
  grep -q "^${fn}()" "$F" || { echo "[ERROR] Missing $fn"; exit 1; }
done

for fn in \
  deploy_runtime_service_exists deploy_wait_service_ready_path \
  deploy_restart_web_proxy_path deploy_restart_php_runtime_path \
  deploy_resolve_http_port_path deploy_verify_application_http_path \
  deploy_optimize_path deploy_health_path
do
  grep -q "^${fn}()" "$R" || { echo "[ERROR] Missing runtime guard $fn"; exit 1; }
done

for fn in deploy_storage_normalize_path deploy_storage_verify_path deploy_storage_repair; do
  grep -q "^${fn}()" "$S" || { echo "[ERROR] Missing storage contract $fn"; exit 1; }
done

# Contract: config cache refresh must be followed by PHP runtime restart.
grep -Fq 'Restart PHP runtime after cache refresh' "$R" || { echo '[ERROR] Missing PHP runtime restart contract'; exit 1; }
grep -Fq 'deploy_restart_php_runtime_path' "$R" || { echo '[ERROR] Missing PHP runtime restart helper call'; exit 1; }

# Contract: Nginx/web must refresh FastCGI upstream after app restart to avoid 502.
grep -Fq 'deploy_restart_web_proxy_path "$project_dir" "$timeout"' "$R" || { echo '[ERROR] Missing web upstream refresh after app restart'; exit 1; }
grep -Fq 'Restart web để refresh FastCGI upstream sau app restart' "$R" || { echo '[ERROR] Missing web restart contract'; exit 1; }

# Contract: Laravel must really boot; php-fpm -t / artisan --version alone is insufficient.
grep -Fq 'php artisan about --no-ansi' "$R" || { echo '[ERROR] Missing Laravel boot verification'; exit 1; }

# Contract: deploy success requires a real local 2xx/3xx HTTP response.
grep -Fq '^[23][0-9][0-9]$' "$R" || { echo '[ERROR] Missing HTTP 2xx/3xx acceptance contract'; exit 1; }
grep -Fq 'Application HTTP verification failed' "$R" || { echo '[ERROR] Missing HTTP failure contract'; exit 1; }

# Public storage contract: shared volume remains private except for the public
# disk, which must be traversable/readable by the separate Nginx container.
grep -Fq 'chmod 2711 storage/app' "$S" || { echo '[ERROR] Missing storage/app traverse permission'; exit 1; }
grep -Fq 'chmod 2755 {}' "$S" || { echo '[ERROR] Missing public directory permission'; exit 1; }
grep -Fq 'chmod 0644 {}' "$S" || { echo '[ERROR] Missing public file permission'; exit 1; }
grep -Fq 'http://127.0.0.1:8080/storage/$probe' "$S" || { echo '[ERROR] Missing Nginx public-storage probe'; exit 1; }
grep -Fq 'deploy_storage_normalize_path "$project_dir"' "$R" || { echo '[ERROR] Runtime health must normalize public storage'; exit 1; }
grep -Fq 'deploy_storage_normalize_path "$project_path"' "$ROOT/modules/site/lib/provision.sh" || { echo '[ERROR] Create Site must normalize public storage'; exit 1; }
grep -Fq -- '--storage-only' "$ROOT/modules/deploy/commands/health.sh" || { echo '[ERROR] Missing storage-only repair command path'; exit 1; }
grep -Fq 'Repair Public Storage' "$ROOT/modules/ui/menus/deploy.sh" || { echo '[ERROR] Missing storage repair UI action'; exit 1; }

# Runtime guard must be active for run/health/optimize entry points.
for cmd in run health optimize; do
  grep -Fq 'modules/deploy/lib/runtime-health.sh' "$ROOT/modules/deploy/commands/$cmd.sh" || {
    echo "[ERROR] Runtime guard not sourced by $cmd"
    exit 1
  }
done

[[ -x "$ROOT/modules/deploy/commands/frontend.sh" ]] || { echo '[ERROR] frontend command is not executable'; exit 1; }
bash -n "$F"
bash -n "$R"
bash -n "$S"
bash -n "$ROOT/modules/deploy/commands/run.sh"
bash -n "$ROOT/modules/deploy/commands/health.sh"
bash -n "$ROOT/modules/deploy/commands/optimize.sh"
bash -n "$ROOT/modules/deploy/commands/frontend.sh"
bash -n "$ROOT/modules/site/lib/provision.sh"
bash -n "$ROOT/modules/ui/menus/deploy.sh"

# Execute the HTTP gate itself against isolated loopback servers.
TMP="$(mktemp -d /tmp/platform-deploy-http-test.XXXXXX)"
PIDS=()
cleanup() {
  local pid
  for pid in "${PIDS[@]:-}"; do kill "$pid" 2>/dev/null || true; done
  rm -rf "$TMP"
}
trap cleanup EXIT

free_port() {
  python3 - <<'PY'
import socket
s=socket.socket()
s.bind(('127.0.0.1',0))
print(s.getsockname()[1])
s.close()
PY
}

wait_port() {
  local port="$1"
  local i
  for i in $(seq 1 30); do
    if python3 - "$port" <<'PY'
import socket,sys
s=socket.socket(); s.settimeout(.2)
try:
    s.connect(('127.0.0.1',int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
    then return 0; fi
    sleep .1
  done
  return 1
}

# Source implementations for executable contract test. Any unexpected die is fatal.
die() { echo "[TEST DIE] $*" >&2; exit 1; }
warn() { :; }
success() { :; }
source "$F"
source "$R"

PORT200="$(free_port)"
printf 'ok\n' > "$TMP/index.html"
python3 -m http.server "$PORT200" --bind 127.0.0.1 --directory "$TMP" >/dev/null 2>&1 &
PIDS+=("$!")
wait_port "$PORT200" || { echo '[ERROR] HTTP 200 fixture did not start'; exit 1; }
printf 'HTTP_PORT=%s\n' "$PORT200" > "$TMP/.docker-platform.env"
deploy_verify_application_http_path "$TMP" 2 >/dev/null || { echo '[ERROR] HTTP 200 fixture must pass'; exit 1; }

PORT500="$(free_port)"
cat > "$TMP/server500.py" <<'PY'
from http.server import BaseHTTPRequestHandler, HTTPServer
import sys
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(500)
        self.end_headers()
        self.wfile.write(b'fail')
    def log_message(self, *args):
        pass
HTTPServer(('127.0.0.1', int(sys.argv[1])), Handler).serve_forever()
PY
python3 "$TMP/server500.py" "$PORT500" >/dev/null 2>&1 &
PIDS+=("$!")
wait_port "$PORT500" || { echo '[ERROR] HTTP 500 fixture did not start'; exit 1; }
printf 'HTTP_PORT=%s\n' "$PORT500" > "$TMP/.docker-platform.env"

if deploy_verify_application_http_path "$TMP" 0 >/dev/null 2>&1; then
  echo '[ERROR] HTTP 500 must block deploy health'
  exit 1
fi

echo "[OK] Deploy Module v1.3 runtime + public storage + application HTTP gate"
