#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OK_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
MISSING_APT=()
MISSING_SPECIAL=()

line() {
  printf '%s\n' '========================================================='
}

ok() {
  OK_COUNT=$((OK_COUNT + 1))
  printf '[OK] %s\n' "$*"
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf '[WARN] %s\n' "$*"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$*"
}

info() {
  printf '[INFO] %s\n' "$*"
}

add_apt() {
  local pkg="$1" existing
  for existing in "${MISSING_APT[@]:-}"; do
    [[ "$existing" == "$pkg" ]] && return 0
  done
  MISSING_APT+=("$pkg")
}

add_special() {
  local item="$1" existing
  for existing in "${MISSING_SPECIAL[@]:-}"; do
    [[ "$existing" == "$item" ]] && return 0
  done
  MISSING_SPECIAL+=("$item")
}

version_ge() {
  local current="$1" minimum="$2"
  [[ -n "$current" && -n "$minimum" ]] || return 1
  [[ "$(printf '%s\n%s\n' "$minimum" "$current" | sort -V | head -n1)" == "$minimum" ]]
}

cmd_version() {
  local cmd="$1"
  case "$cmd" in
    bash) bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    git) git --version | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    python3) python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    jq) jq --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    curl) curl --version | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    ssh) ssh -V 2>&1 | grep -oE '[0-9]+\.[0-9]+(p[0-9]+)?' | head -n1 | tr 'p' '.' ;;
    docker) docker --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    nginx) nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    certbot) certbot --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    make) make --version | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    rsync) rsync --version | head -n1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 ;;
    *) return 1 ;;
  esac
}

check_cmd() {
  local cmd="$1" label="$2" apt_pkg="$3" minimum="${4:-}" version=""
  if ! command -v "$cmd" >/dev/null 2>&1; then
    fail "$label chưa được cài (command: $cmd)."
    [[ -n "$apt_pkg" ]] && add_apt "$apt_pkg"
    return 1
  fi

  if [[ -n "$minimum" ]]; then
    version="$(cmd_version "$cmd" 2>/dev/null || true)"
    if [[ -n "$version" ]] && version_ge "$version" "$minimum"; then
      ok "$label $version (>= $minimum)."
    elif [[ -n "$version" ]]; then
      warn "$label $version thấp hơn baseline khuyến nghị $minimum."
    else
      ok "$label có sẵn; không đọc được version tự động."
    fi
  else
    ok "$label có sẵn."
  fi
}

show_help() {
  cat <<'EOF'
Laravel Deployment Platform v2 — check-system.sh

MỤC ĐÍCH
  Kiểm tra VPS/Ubuntu hiện tại có đủ điều kiện để cài đặt, phát triển và vận hành
  laravel-deployment-platform-v2 hay chưa. Script chỉ đọc trạng thái hệ thống;
  KHÔNG tự cài package, KHÔNG thay firewall, KHÔNG sửa Docker/Nginx/Inventory.

CÁCH DÙNG
  ./check-system.sh
  bash check-system.sh
  ./check-system.sh --help

EXIT CODE
  0  READY: không có blocker bắt buộc.
  1  BLOCKED: thiếu dependency hoặc service bắt buộc.
  2  Tham số không hợp lệ.

HỆ ĐIỀU HÀNH KHUYẾN NGHỊ
  Ubuntu Server 24.04 LTS (production baseline ưu tiên).
  Ubuntu 26.04 LTS có thể dùng sau khi chạy đầy đủ regression/staging validation.

HOST SOFTWARE KHUYẾN NGHỊ
  Bash              5.2+
  Git               2.43+
  Python            3.12+
  OpenSSH           9.6+
  Docker Engine     stable official channel (khuyến nghị current stable)
  Docker Compose    v2 plugin
  Docker Buildx     plugin current stable
  Nginx host        1.24+
  Certbot           2.9+ + nginx plugin
  jq                1.7+
  GNU Make          4.x
  rsync             3.2+

PACKAGE UBUNTU CƠ BẢN
  apt update
  apt install -y \
    ca-certificates curl wget git openssh-client openssh-server \
    python3 python3-venv python3-pip jq make rsync \
    tar gzip unzip xz-utils openssl gnupg lsb-release \
    dnsutils iproute2 netcat-openbsd util-linux coreutils \
    findutils grep sed gawk nginx certbot python3-certbot-nginx ufw

CÀI DOCKER CE TỪ OFFICIAL APT REPOSITORY
  Không ưu tiên docker.io/docker-compose v1 cho VPS production mới.

  apt update
  apt install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat >/etc/apt/sources.list.d/docker.sources <<EOF_DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker

VERIFY DOCKER
  docker --version
  docker compose version
  docker buildx version
  docker run --rm hello-world

NGINX + CERTBOT
  systemctl enable --now nginx
  nginx -t
  certbot --version
  certbot plugins | grep nginx

FIREWALL CƠ BẢN
  ufw allow OpenSSH
  ufw allow 'Nginx Full'
  ufw enable
  ufw status verbose

LƯU Ý VỀ RUNTIME LARAVEL
  Platform quản lý Laravel site bằng Docker Compose. Host VPS KHÔNG cần cài PHP,
  Node.js, MariaDB server hoặc Redis server chỉ vì application image đang dùng chúng.
  Các runtime đó nên nằm trong Dockerfile/compose của từng Laravel repository.

  Baseline application hiện thường gặp:
    PHP       8.3
    Node.js   22
    Composer  2.8
    MariaDB   11.8
    Redis     7.4-alpine
    Nginx     1.28-alpine

CẤU HÌNH GITHUB SSH
  Với VPS dùng nhiều GitHub account, nên dùng SSH Host alias riêng theo owner:

    Host github-tungocvan
        HostName github.com
        User git
        IdentityFile /root/.ssh/github_tungocvan_ed25519
        IdentitiesOnly yes

  Kiểm tra:
    ssh -T git@github-tungocvan

  Chỉ chia sẻ file .pub. KHÔNG cat/share private SSH key.

CLONE PROJECT
  cd /opt
  git clone \
    git@github-tungocvan:tungocvan/laravel-deployment-platform-v2.git \
    /opt/laravel-deployment-platform-v2
  cd /opt/laravel-deployment-platform-v2
  git checkout main
  git pull --ff-only

KIỂM TRA HỆ THỐNG SAU KHI CLONE
  cd /opt/laravel-deployment-platform-v2
  ./check-system.sh

CÀI PLATFORM CLI
  cd /opt/laravel-deployment-platform-v2
  sudo ./install.sh

  Expected:
    /usr/local/bin/platform-v2 -> /opt/laravel-deployment-platform-v2/bin/platform

CHẠY PLATFORM
  platform-v2
  platform-v2 menu
  platform-v2 site list
  platform-v2 deploy health <site>

  Lưu ý:
    platform-v2 0   # SAI: 0 bị hiểu là module name
    Trong menu mới nhập 0 để Exit.
    Command `platform` có thể là Platform v1 cũ; Platform 2.x dùng `platform-v2`.

KIỂM TRA SOURCE / REGRESSION
  cd /opt/laravel-deployment-platform-v2
  make test
  make lint

TÀI LIỆU CẦN ĐỌC
  INFORMATION.md
  docs/VPS-DEPLOYMENT-GUIDE.md
  docs/AI-HANDOFF.md

SAU KHI CÀI XONG
  1. ./check-system.sh phải không có FAIL.
  2. make test phải PASS.
  3. make lint phải PASS.
  4. platform-v2 mở được Operations Console.
  5. Nginx: nginx -t PASS.
  6. Docker daemon + docker compose hoạt động.
  7. Certbot nginx plugin có sẵn nếu dùng SSL.
EOF
}

case "${1:-}" in
  -h|--help)
    show_help
    exit 0
    ;;
  "") ;;
  *)
    printf '[ERROR] Tham số không hợp lệ: %s\n\n' "$1" >&2
    show_help >&2
    exit 2
    ;;
esac

line
echo 'Laravel Deployment Platform v2 — SYSTEM READINESS CHECK'
line
printf 'Repository : %s\n' "$SCRIPT_DIR"
printf 'User       : %s (uid=%s)\n' "$(id -un)" "$(id -u)"
printf 'Hostname   : %s\n' "$(hostname 2>/dev/null || echo unknown)"
printf 'Kernel     : %s\n' "$(uname -srmo 2>/dev/null || uname -a)"
line

echo
printf '%s\n' '----- 1. OPERATING SYSTEM -----'
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  if [[ "${ID:-}" == "ubuntu" ]]; then
    case "${VERSION_ID:-}" in
      24.04) ok "Ubuntu ${VERSION_ID} LTS — baseline production khuyến nghị." ;;
      26.04) ok "Ubuntu ${VERSION_ID} LTS — hỗ trợ sau regression/staging validation." ;;
      22.04) warn "Ubuntu ${VERSION_ID} LTS có thể chạy nhưng nên lên kế hoạch nâng 24.04 cho VPS mới." ;;
      *) warn "Ubuntu ${VERSION_ID:-unknown}; baseline được tài liệu hóa là 24.04 LTS." ;;
    esac
  else
    fail "OS hiện tại là ${PRETTY_NAME:-${ID:-unknown}}; Platform hiện được chuẩn hóa/test cho Ubuntu." 
  fi
else
  fail 'Không đọc được /etc/os-release.'
fi

arch="$(uname -m 2>/dev/null || true)"
case "$arch" in
  x86_64|amd64) ok "Architecture: $arch." ;;
  aarch64|arm64) warn "Architecture: $arch. Có thể dùng nếu tất cả application image hỗ trợ arm64." ;;
  *) warn "Architecture chưa được baseline rõ: ${arch:-unknown}." ;;
esac

if [[ "$(id -u)" -eq 0 ]]; then
  ok 'Đang chạy bằng root — phù hợp cho readiness VPS toàn hệ thống.'
else
  warn 'Không chạy bằng root; một số test Nginx/system service có thể chỉ kiểm tra hạn chế. install.sh cần sudo/root.'
fi

echo
printf '%s\n' '----- 2. HOST RESOURCES -----'
cpu_count="$(nproc 2>/dev/null || echo 0)"
if [[ "$cpu_count" -ge 4 ]]; then
  ok "CPU: ${cpu_count} vCPU."
elif [[ "$cpu_count" -ge 2 ]]; then
  warn "CPU: ${cpu_count} vCPU; phù hợp dev/nhẹ, production nhiều site nên 4+ vCPU."
else
  warn "CPU: ${cpu_count} vCPU; có thể thiếu cho Docker build/multi-site."
fi

mem_mb="$(awk '/MemTotal:/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
if [[ "$mem_mb" -ge 7800 ]]; then
  ok "RAM: khoảng ${mem_mb} MB."
elif [[ "$mem_mb" -ge 3800 ]]; then
  warn "RAM: khoảng ${mem_mb} MB; production nhiều site nên 8 GB+."
else
  warn "RAM: khoảng ${mem_mb} MB; Docker build/database/queue có thể thiếu bộ nhớ."
fi

free_mb="$(df -Pm /opt 2>/dev/null | awk 'NR==2 {print $4}' || true)"
[[ -n "$free_mb" ]] || free_mb="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || echo 0)"
if [[ "$free_mb" -ge 20480 ]]; then
  ok "Disk free: khoảng $((free_mb / 1024)) GB."
elif [[ "$free_mb" -ge 10240 ]]; then
  warn "Disk free: khoảng $((free_mb / 1024)) GB; nên có >=20 GB free, production thường cần 80 GB+ tổng disk."
else
  warn "Disk free thấp: khoảng $((free_mb / 1024)) GB. Docker images/backups dễ làm đầy disk."
fi

echo
printf '%s\n' '----- 3. REQUIRED COMMANDS -----'
check_cmd bash 'Bash' bash 5.2 || true
check_cmd git 'Git' git 2.43 || true
check_cmd python3 'Python 3' python3 3.12 || true
check_cmd jq 'jq' jq 1.7 || true
check_cmd curl 'curl' curl 8.0 || true
check_cmd ssh 'OpenSSH client' openssh-client 9.6 || true
check_cmd ssh-keygen 'ssh-keygen' openssh-client || true
check_cmd make 'GNU Make' make 4.0 || true
check_cmd rsync 'rsync' rsync 3.2 || true
check_cmd tar 'tar' tar || true
check_cmd gzip 'gzip' gzip || true
check_cmd unzip 'unzip' unzip || true
check_cmd openssl 'OpenSSL CLI' openssl || true
check_cmd ss 'ss/iproute2' iproute2 || true
check_cmd flock 'flock/util-linux' util-linux || true
check_cmd realpath 'realpath/coreutils' coreutils || true
check_cmd find 'find/findutils' findutils || true
check_cmd xargs 'xargs/findutils' findutils || true

echo
printf '%s\n' '----- 4. DOCKER ENGINE / COMPOSE -----'
if command -v docker >/dev/null 2>&1; then
  docker_version="$(cmd_version docker 2>/dev/null || true)"
  [[ -n "$docker_version" ]] && ok "Docker Engine CLI: $docker_version." || ok 'Docker Engine CLI có sẵn.'

  if docker info >/dev/null 2>&1; then
    ok 'Docker daemon hoạt động và user hiện tại truy cập được.'
  else
    fail 'Docker CLI có nhưng không truy cập được daemon. Kiểm tra systemctl status docker / permission docker.sock.'
  fi

  if docker compose version >/dev/null 2>&1; then
    compose_version="$(docker compose version --short 2>/dev/null || docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1 || true)"
    ok "Docker Compose v2 plugin: ${compose_version:-available}."
  else
    fail 'Thiếu Docker Compose v2 plugin (`docker compose`).'
    add_special 'docker-compose-plugin'
  fi

  if docker buildx version >/dev/null 2>&1; then
    ok 'Docker Buildx plugin hoạt động.'
  else
    fail 'Thiếu Docker Buildx plugin.'
    add_special 'docker-buildx-plugin'
  fi
else
  fail 'Docker Engine chưa được cài.'
  add_special 'Docker CE official repository'
fi

echo
printf '%s\n' '----- 5. NGINX HOST / TLS -----'
if check_cmd nginx 'Nginx host' nginx 1.24; then
  if [[ "$(id -u)" -eq 0 ]]; then
    if nginx -t >/dev/null 2>&1; then
      ok 'nginx -t PASS.'
    else
      fail 'nginx -t FAIL. Kiểm tra /etc/nginx trước khi vận hành site.'
    fi
  else
    if nginx -t >/dev/null 2>&1; then
      ok 'nginx -t PASS.'
    else
      warn 'nginx -t chưa PASS ở user hiện tại; chạy lại check-system.sh bằng sudo/root để xác minh.'
    fi
  fi
fi

if check_cmd certbot 'Certbot' certbot 2.9; then
  if certbot plugins 2>/dev/null | grep -q 'nginx'; then
    ok 'Certbot nginx plugin có sẵn.'
  else
    fail 'Certbot có nhưng thiếu nginx plugin.'
    add_apt 'python3-certbot-nginx'
  fi
fi

echo
printf '%s\n' '----- 6. SYSTEM SERVICES / NETWORK BASICS -----'
if command -v systemctl >/dev/null 2>&1; then
  ok 'systemctl có sẵn.'
  if systemctl is-enabled docker >/dev/null 2>&1; then
    ok 'Docker service được enable khi boot.'
  elif command -v docker >/dev/null 2>&1; then
    warn 'Docker service chưa xác nhận enable khi boot.'
  fi
  if systemctl is-enabled nginx >/dev/null 2>&1; then
    ok 'Nginx service được enable khi boot.'
  elif command -v nginx >/dev/null 2>&1; then
    warn 'Nginx service chưa xác nhận enable khi boot.'
  fi
else
  fail 'Không có systemctl/systemd; Platform VPS baseline hiện dựa trên Ubuntu systemd.'
fi

if command -v getent >/dev/null 2>&1; then
  if getent hosts github.com >/dev/null 2>&1; then
    ok 'DNS resolve github.com hoạt động.'
  else
    fail 'Không resolve được github.com; Git operations có thể thất bại.'
  fi
else
  warn 'Không có getent; không test DNS baseline.'
fi

if curl -fsSI --max-time 5 https://github.com >/dev/null 2>&1; then
  ok 'Outbound HTTPS tới github.com hoạt động.'
else
  warn 'Không xác minh được outbound HTTPS tới github.com trong 5 giây.'
fi

if command -v ufw >/dev/null 2>&1; then
  ufw_status="$(ufw status 2>/dev/null | head -n1 || true)"
  info "UFW: ${ufw_status:-không đọc được trạng thái}."
else
  warn 'UFW chưa được cài; không bắt buộc nếu VPS dùng firewall policy khác, nhưng cần có firewall rõ ràng.'
  add_apt 'ufw'
fi

echo
printf '%s\n' '----- 7. PLATFORM REPOSITORY LAYOUT -----'
for path in bin/platform core modules config tools Makefile install.sh README.md; do
  if [[ -e "$SCRIPT_DIR/$path" ]]; then
    ok "Có $path."
  else
    fail "Thiếu repository path bắt buộc: $path"
  fi
done

if [[ -f "$SCRIPT_DIR/INFORMATION.md" ]]; then
  ok 'Có INFORMATION.md (AI/developer handoff).'
else
  warn 'Chưa có INFORMATION.md trên branch hiện tại.'
fi

if [[ -f "$SCRIPT_DIR/docs/VPS-DEPLOYMENT-GUIDE.md" ]]; then
  ok 'Có docs/VPS-DEPLOYMENT-GUIDE.md.'
else
  warn 'Chưa có docs/VPS-DEPLOYMENT-GUIDE.md trên branch hiện tại.'
fi

if [[ -x "$SCRIPT_DIR/bin/platform" ]]; then
  ok 'bin/platform executable.'
else
  warn 'bin/platform chưa executable; install.sh sẽ chuẩn hóa permission.'
fi

if [[ -d /opt ]]; then
  ok '/opt tồn tại.'
else
  fail '/opt không tồn tại.'
fi

if [[ -d /opt/projects ]]; then
  ok '/opt/projects tồn tại.'
else
  warn '/opt/projects chưa tồn tại; tạo trước khi provision site mới.'
fi

if command -v platform-v2 >/dev/null 2>&1; then
  platform_bin="$(command -v platform-v2)"
  platform_target="$(readlink -f "$platform_bin" 2>/dev/null || true)"
  ok "platform-v2 đã được cài: $platform_bin${platform_target:+ -> $platform_target}."
else
  warn 'CLI platform-v2 chưa được cài/symlink. Sau khi readiness PASS, chạy sudo ./install.sh.'
fi

echo
printf '%s\n' '----- 8. OPTIONAL DEVELOPMENT / OPERATIONS TOOLS -----'
if command -v shellcheck >/dev/null 2>&1; then
  ok 'shellcheck có sẵn — hữu ích khi phát triển Bash.'
else
  warn 'shellcheck chưa cài; không bắt buộc runtime nhưng khuyến nghị developer cài.'
fi
if command -v gh >/dev/null 2>&1; then
  ok 'GitHub CLI (gh) có sẵn.'
else
  info 'GitHub CLI (gh) chưa cài; optional, không cần cho Platform runtime.'
fi
if command -v dig >/dev/null 2>&1; then
  ok 'dig/dnsutils có sẵn.'
else
  warn 'dig chưa cài; khuyến nghị dnsutils để debug DNS/SSL.'
  add_apt 'dnsutils'
fi
if command -v nc >/dev/null 2>&1; then
  ok 'netcat có sẵn.'
else
  warn 'netcat chưa cài; hữu ích debug upstream 502.'
  add_apt 'netcat-openbsd'
fi

echo
line
echo 'RESULT'
line
printf 'OK      : %d\n' "$OK_COUNT"
printf 'WARN    : %d\n' "$WARN_COUNT"
printf 'FAIL    : %d\n' "$FAIL_COUNT"

if [[ "${#MISSING_APT[@]}" -gt 0 ]]; then
  echo
  echo 'Ubuntu packages cần/có thể cần cài:'
  printf '  apt update && apt install -y'
  printf ' %q' "${MISSING_APT[@]}"
  printf '\n'
fi

if [[ "${#MISSING_SPECIAL[@]}" -gt 0 ]]; then
  echo
  echo 'Thành phần cần cài theo hướng dẫn riêng:'
  printf '  - %s\n' "${MISSING_SPECIAL[@]}"
fi

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo
  echo '[BLOCKED] VPS chưa đủ điều kiện bắt buộc cho Platform.'
  echo 'Chạy: ./check-system.sh --help'
  echo 'Đọc : docs/VPS-DEPLOYMENT-GUIDE.md'
  exit 1
fi

echo
if [[ "$WARN_COUNT" -gt 0 ]]; then
  echo '[READY WITH WARNINGS] Không có blocker, nhưng nên review các cảnh báo trước production.'
else
  echo '[READY] Hệ thống đáp ứng các điều kiện kiểm tra hiện tại.'
fi

echo 'Tiếp theo: make test && make lint && sudo ./install.sh'
exit 0
