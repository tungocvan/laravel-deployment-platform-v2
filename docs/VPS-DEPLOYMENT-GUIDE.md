# Laravel Deployment Platform v2 — VPS Deployment Guide

> Hướng dẫn dựng một VPS Ubuntu mới để chạy `laravel-deployment-platform-v2` ổn định, dễ bảo trì và phù hợp mô hình nhiều Laravel site chạy Docker Compose.

**Cập nhật khuyến nghị: 2026-08-21.** Version exact của package có thể thay đổi theo thời gian; ưu tiên LTS/stable channel và test `make test` + `make lint` sau cài đặt/nâng cấp.

---

## 1. Mục tiêu kiến trúc VPS

Mô hình khuyến nghị:

```text
Internet
  |
  | 80/443
  v
Host Nginx + Certbot
  |
  | 127.0.0.1:<HTTP_PORT của site>
  v
Docker Compose project của từng Laravel site
  |
  +-- web (nginx container)
  +-- app (php-fpm)
  +-- queue
  +-- scheduler
  +-- socket
  +-- db (MariaDB)
  +-- redis

Host Platform CLI
  /opt/laravel-deployment-platform-v2
  /usr/local/bin/platform-v2

Managed projects
  /opt/projects/<site>
```

Host nên giữ vai trò orchestration/reverse proxy. PHP/Node/MariaDB/Redis application runtime nên nằm trong Docker images của source Laravel, tránh cài duplicate runtime trên host nếu không cần.

---

## 2. OS khuyến nghị

### Preferred production baseline

```text
Ubuntu Server 24.04 LTS (Noble), amd64/x86_64
```

Lý do:

- mature LTS baseline;
- Standard Support tới 2029;
- Docker Engine chính thức hỗ trợ Ubuntu 24.04;
- Bash/Python/Git/Nginx đủ mới;
- ổn định hơn cho production lâu dài so với đổi major OS ngay khi release mới xuất hiện.

### Alternative

```text
Ubuntu Server 26.04 LTS
```

Docker hiện cũng hỗ trợ 26.04. Có thể dùng cho VPS mới sau khi chạy đầy đủ Platform regression + site staging validation. Nếu ưu tiên maturity hơn latest kernel/userspace, 24.04 LTS vẫn là baseline dễ kiểm soát.

### Không khuyến nghị cho VPS mới

- Ubuntu non-LTS/interim.
- Ubuntu 20.04 cho deployment mới.
- Docker convenience script cho production nếu có thể dùng official apt repository.

---

## 3. Sizing VPS

Tùy số site và workload. Baseline thực tế cho vài Laravel site vừa/nhỏ:

```text
CPU   : 4 vCPU trở lên
RAM   : 8 GB trở lên
Disk  : 80–160 GB SSD/NVMe trở lên
Swap  : 2–4 GB tùy RAM/workload
Network: public IPv4 ổn định; IPv6 nếu sử dụng
```

Nếu site có LibreOffice/document conversion, queue nặng, image processing hoặc nhiều MariaDB container:

```text
CPU   : 8 vCPU+
RAM   : 16 GB+
Disk  : NVMe + backup capacity riêng
```

Không đặt memory limits tổng của tất cả containers vượt xa RAM vật lý.

---

## 4. Host software — version recommendation

| Component | Khuyến nghị | Ghi chú |
|---|---|---|
| Ubuntu | 24.04 LTS | baseline production |
| Bash | 5.2+ | Ubuntu 24.04 đáp ứng |
| Git | 2.43+ | đủ cho worktree/force-with-lease/current workflows |
| Python | 3.12+ | dùng cho JSON/state helpers |
| OpenSSH | 9.6+ | multi GitHub identity / Ed25519 |
| Docker Engine | stable channel, hiện 29.x phù hợp | cài từ Docker official apt repo |
| Docker Compose | Compose plugin v2, latest stable cùng Docker repo | dùng `docker compose`, không ưu tiên legacy `docker-compose` v1 |
| Buildx | Docker buildx plugin current stable | cần multi-stage/build |
| Nginx host | 1.24+ | Ubuntu repo phù hợp; không bắt buộc mainline |
| Certbot | 2.9+ hoặc stable distro/snap | cần nginx plugin |
| curl | 8.x | health/download |
| jq | 1.7+ | hữu ích diagnostics; Platform chủ yếu dùng Python cho JSON |
| make | GNU Make 4.x | chạy regression |
| rsync | 3.2+ | vận hành/backup helper khi cần |
| tar/gzip/unzip | distro stable | backup/archive |
| openssl | distro supported | TLS diagnostics |
| dnsutils | distro stable | `dig`/DNS diagnostics |
| iproute2 | distro stable | `ss` port detection |
| netcat-openbsd | distro stable | network/upstream diagnostics |

### Application runtime versions — không phải host requirement

Các Laravel source hiện có thể dùng Docker images theo dòng:

```text
PHP       8.3
Node.js   22
Composer  2.8
MariaDB   11.8
Redis     7.4-alpine
Nginx     1.28-alpine (web container)
```

Đây là version của **application Dockerfile/compose**, không có nghĩa VPS host cần `apt install php nodejs mariadb-server redis-server`.

Node 22 vẫn là LTS nhưng đã ở Maintenance trong 2026; Node 24 hiện là LTS. **Không tự đổi application Node 22 -> 24 chỉ ở Platform host.** Việc nâng Node/PHP/MariaDB/Redis phải được thực hiện trong application repository, build/test riêng.

---

## 5. Initial Ubuntu preparation

Login root hoặc user có sudo:

```bash
sudo -i
apt update
apt full-upgrade -y
apt install -y \
  ca-certificates \
  curl \
  wget \
  git \
  openssh-client \
  openssh-server \
  python3 \
  python3-venv \
  python3-pip \
  jq \
  make \
  rsync \
  tar \
  gzip \
  unzip \
  xz-utils \
  openssl \
  gnupg \
  lsb-release \
  dnsutils \
  iproute2 \
  netcat-openbsd \
  nano \
  vim \
  htop
```

Verify:

```bash
bash --version | head -1
git --version
python3 --version
ssh -V 2>&1
curl --version | head -1
```

---

## 6. Timezone / clock

Platform logs/audit/backup timestamps phụ thuộc system clock.

```bash
timedatectl
sudo timedatectl set-timezone Asia/Ho_Chi_Minh
sudo systemctl enable --now systemd-timesyncd
```

Verify:

```bash
timedatectl status
```

Container/app timezone vẫn nên được cấu hình độc lập trong source Laravel nếu cần.

---

## 7. Create platform directories

```bash
mkdir -p /opt/projects
mkdir -p /opt/laravel-deployment-platform-v2
chmod 755 /opt /opt/projects
```

Không tạo production site bằng cách copy thủ công tùy ý nếu Platform Site Provisioning có thể làm việc đó.

---

## 8. Install Docker Engine from official repository

Không ưu tiên Ubuntu package `docker.io` nếu mục tiêu là theo Docker CE stable chính thức.

Remove conflicting packages nếu có:

```bash
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt remove -y "$pkg" 2>/dev/null || true
done
```

Add Docker official repository:

```bash
apt update
apt install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update
apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
```

Verify:

```bash
docker --version
docker compose version
docker buildx version
systemctl status docker --no-pager
docker run --rm hello-world
```

Enable at boot:

```bash
systemctl enable docker
```

### Docker upgrade policy

- dùng stable channel;
- không auto major-upgrade ngay trước production deployment lớn;
- sau Docker upgrade chạy `docker compose version`, Platform tests và health của site;
- Docker firewall behavior cần được tính khi dùng UFW/nftables.

---

## 9. Docker daemon operational defaults

Docker `local` log driver thường được source compose chọn theo từng site. Host vẫn nên theo dõi disk:

```bash
docker system df
df -h
df -ih
```

Không chạy `docker system prune -a --volumes` tự động trên production multi-site host.

Nếu cần cleanup, inspect từng resource/project trước.

---

## 10. Install Nginx host

```bash
apt install -y nginx
systemctl enable --now nginx
nginx -v
nginx -t
```

Ports 80/443 phải dành cho host Nginx, không publish Laravel site trực tiếp ra `0.0.0.0:80/443`.

Laravel web containers nên publish kiểu:

```text
127.0.0.1:<HTTP_PORT>:8080
```

Check listeners:

```bash
ss -lntp
```

---

## 11. Install Certbot

Option đơn giản trên Ubuntu:

```bash
apt install -y certbot python3-certbot-nginx
certbot --version
```

Verify timer:

```bash
systemctl list-timers | grep -i certbot || true
```

Alternative là snap Certbot nếu policy của server chọn snap; chỉ nên có một installation path rõ ràng để tránh nhầm binary/config.

Platform SSL module kỳ vọng `certbot` command hoạt động.

---

## 12. Firewall

Nếu dùng UFW:

```bash
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw enable
ufw status verbose
```

Quan trọng: Docker quản lý iptables rules riêng. Docker official docs cảnh báo firewall integration cần hiểu `DOCKER-USER` chain. Không dựa vào UFW đơn thuần để kết luận Docker published port đã bị chặn.

Platform compose nên publish application HTTP/socket lên loopback khi không cần public direct access.

---

## 13. GitHub SSH identity setup

### 13.1 Không dùng một key mặc định cho mọi owner

VPS có thể cần nhiều GitHub account. Dùng SSH aliases.

Create owner-specific key:

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh

ssh-keygen -t ed25519 \
  -f /root/.ssh/github_tungocvan_ed25519 \
  -C 'vps-platform:tungocvan'

chmod 600 /root/.ssh/github_tungocvan_ed25519
chmod 644 /root/.ssh/github_tungocvan_ed25519.pub
```

**Chỉ copy public key:**

```bash
cat /root/.ssh/github_tungocvan_ed25519.pub
```

Không cat/share file private key.

### 13.2 SSH config

```sshconfig
Host github-tungocvan
    HostName github.com
    User git
    IdentityFile /root/.ssh/github_tungocvan_ed25519
    IdentitiesOnly yes
```

Permissions:

```bash
chmod 600 /root/.ssh/config
```

Test:

```bash
ssh -T git@github-tungocvan
```

Expected identity:

```text
Hi tungocvan! You've successfully authenticated...
```

### 13.3 Platform menu 18

Sau khi Platform được cài, có thể dùng:

```text
platform-v2
→ Sites & Repository
→ 18) Kiểm tra quyền repository / SSH key
```

Flow sẽ test READ + WRITE + DELETE bằng temporary ref. Nó ưu tiên existing owner alias trước khi đề nghị tạo key mới.

---

## 14. Clone Platform repository

Preferred production remote trên VPS có owner alias:

```bash
cd /opt
rm -rf /opt/laravel-deployment-platform-v2.new 2>/dev/null || true

git clone \
  git@github-tungocvan:tungocvan/laravel-deployment-platform-v2.git \
  /opt/laravel-deployment-platform-v2

cd /opt/laravel-deployment-platform-v2
git checkout main
git pull --ff-only
```

Nếu canonical `github.com` identity đúng account thì canonical URL cũng được, nhưng multi-account VPS nên dùng alias rõ ràng.

Verify:

```bash
git remote -v
git branch --show-current
git log -3 --oneline --decorate
```

---

## 15. Install Platform CLI

Repository có `install.sh`:

```bash
cd /opt/laravel-deployment-platform-v2
chmod +x install.sh
./install.sh
```

Script mặc định:

```text
install/copy -> /opt/laravel-deployment-platform-v2
create state/sites.json nếu chưa có
chmod shell scripts executable
symlink /usr/local/bin/platform-v2 -> bin/platform
```

Nếu đã clone trực tiếp đúng destination, vẫn có thể dùng script để chuẩn hóa permissions/symlink; nhưng trước khi chạy trên server có state thật, luôn backup/inspect state.

Verify:

```bash
which platform-v2
readlink -f "$(command -v platform-v2)"
platform-v2 --help
```

Expected symlink target:

```text
/opt/laravel-deployment-platform-v2/bin/platform
```

---

## 16. Platform environment configuration

Tham khảo:

```text
config/platform.env.example
```

Default:

```text
PLATFORM_HOME=/opt/laravel-deployment-platform-v2
PROJECTS_ROOT=/opt/projects
DOCKER_PLATFORM_DIR=/opt/laravel-docker-platform
INVENTORY_FILE=/opt/laravel-deployment-platform-v2/state/sites.json
PLATFORM_DEFAULT_SITE_REPO=git@github.com:tungocvan/laravel-shop.git
START_HTTP_PORT=8081
START_SOCKET_PORT=6001
```

Nếu runtime đọc config override từ file/env khác, follow implementation hiện tại trong `core`/module; không invent config location.

---

## 17. State initialization

Fresh install inventory baseline:

```json
{
  "schema_version": 2,
  "sites": []
}
```

Verify:

```bash
cat /opt/laravel-deployment-platform-v2/state/sites.json
```

Production state:

- không commit;
- backup trước migration lớn;
- không copy Inventory từ VPS khác nếu paths/ports/resources không tương ứng.

---

## 18. Run regression before first site

```bash
cd /opt/laravel-deployment-platform-v2
make test
make lint
```

Expected:

```text
all tests exit 0
lint exit 0
```

Audit tests có thể in warning intentional về `/proc/platform-audit-denied`; xem exit/result cuối thay vì chỉ nhìn warning.

Nếu regression fail trên fresh VPS, không provision production site cho tới khi hiểu nguyên nhân.

---

## 19. Verify host prerequisites checklist

```bash
command -v bash
command -v git
command -v python3
command -v docker
command -v nginx
command -v certbot
command -v ssh
command -v curl
command -v make

systemctl is-active docker
systemctl is-active nginx

docker compose version
nginx -t
```

Network:

```bash
ss -lntp | grep -E ':22|:80|:443' || true
curl -I https://github.com
ssh -T git@github-tungocvan || true
```

---

## 20. DNS prerequisites before Create Site

Trước SSL issue:

- domain A/AAAA phải trỏ đúng server/proxy strategy;
- port 80/443 phải reachable;
- nếu Cloudflare proxy gây HTTP-01 issue, có thể cần temporarily DNS Only tùy flow;
- tránh duplicate DNS records ngoài ý muốn.

Useful:

```bash
dig +short example.com A
dig +short example.com AAAA
curl -I http://example.com
```

Dùng Platform Doctor/Infrastructure menu thay vì chỉ test tay khi Platform đã quản lý site.

---

## 21. Create first site

Interactive:

```bash
platform-v2
```

Chọn:

```text
Sites & Repository
→ Create Site
```

Platform cần quản lý:

```text
name
domain
repository
branch
path
http port
socket port
database
Docker identity
Nginx
SSL
Inventory
```

Không tự tạo compose project name `laravel-app` cho nhiều site.

Sau create:

```bash
platform-v2 site show <site>
platform-v2 site doctor <site>
platform-v2 deploy health <site>
```

---

## 22. Application source requirements

Một source Laravel để Platform vận hành tốt thường cần:

```text
artisan
composer.json / composer.lock
Dockerfile
compose.yaml
.env hoặc env template strategy phù hợp
docker/nginx/default.conf
docker/php/... nếu Dockerfile dùng
public/
storage/
bootstrap/cache
```

Nếu có queue/socket/scheduler, compose services phải consistent với Platform deploy/health contracts.

Dockerfile multi-stage frontend được ưu tiên; khi frontend nằm trong Docker stage, host không cần Node/npm.

---

## 23. Recommended application Docker image versions

Đây là baseline đã được sử dụng tốt trong các source hiện tại, không phải auto-upgrade mandate:

```dockerfile
# PHP
php:8.3-cli-bookworm
php:8.3-fpm-bookworm

# Composer
composer:2.8

# Node
node:22-bookworm-slim

# Nginx application web
nginx:1.28-alpine

# MariaDB
mariadb:11.8

# Redis
redis:7.4-alpine
```

### Upgrade guidance

- PHP: upgrade minor security releases trong cùng supported branch trước; major/minor branch change cần application test.
- Node: Node 24 là LTS trong 2026, nhưng source đang dùng Node 22 thì chỉ nâng sau `npm ci`/build/test compatibility.
- MariaDB: database upgrade cần backup + verify + migration/rollback plan.
- Redis: check client/server protocol compatibility và persistence.
- Nginx container: check config syntax/modules trước upgrade.

Platform host dependency không nên ép application runtime upgrade.

---

## 24. Nginx host configuration strategy

Platform Nginx module nên tạo config per-site và symlink enable theo Ubuntu convention.

Verify global config trước reload:

```bash
nginx -t
```

Không reload nếu syntax fail.

Detect conflicts:

```bash
platform-v2 nginx conflicts <domain> 2>/dev/null || true
```

Nếu command naming thay đổi, kiểm tra module help/source hiện tại.

---

## 25. SSL strategy

Certbot certificate issue phải xảy ra sau khi Nginx HTTP config hợp lệ.

Workflow mental:

```text
DNS ready
→ Nginx config enabled
→ nginx -t
→ HTTP reachable
→ certbot --nginx
→ verify certificate
```

Không xóa certificate đang được enabled Nginx config reference nếu SSL module đang bảo vệ contract đó.

---

## 26. Ports policy

Default allocation range bắt đầu:

```text
HTTP   8081+
Socket 6001+
```

Platform Inventory/Doctor phải xét:

- managed site ports;
- reserved resources;
- host listeners;
- Docker published ports.

Không tự chọn port chỉ bằng cách “nhìn sites.json” vì listener ngoài Inventory vẫn có thể chiếm port.

Useful diagnostics:

```bash
ss -lntp
docker ps --format 'table {{.Names}}\t{{.Ports}}'
platform-v2 site list
```

---

## 27. Backup storage planning

Backup source/database/storage có thể tăng nhanh.

Monitor:

```bash
du -sh /opt/* 2>/dev/null | sort -h
df -h
```

Khuyến nghị:

- local SSD backup để restore nhanh;
- thêm off-server backup/object storage cho disaster recovery;
- verify backup, không chỉ copy file;
- định kỳ test restore trên staging/new identity.

Không coi Docker volume là backup.

---

## 28. Security hardening baseline

### SSH

- dùng Ed25519 keys;
- disable password login khi đã có tested key access;
- cân nhắc disable direct root SSH nếu operational model cho phép;
- backup console/provider access trước khi harden SSH.

### GitHub

- one identity/alias per account hoặc repo khi cần;
- private key chmod 600;
- không paste private key vào AI/ticket;
- Deploy Key chỉ bật write nếu workflow thực sự cần push/delete.

### Host

```bash
apt install -y unattended-upgrades
```

Cấu hình security updates theo maintenance policy; không auto-reboot production vào thời điểm không kiểm soát.

### Secrets

Không commit:

```text
.env
state production secrets
SSH private keys
TLS private keys
database dumps
API tokens
```

---

## 29. Production update workflow cho Platform code

```bash
cd /opt/laravel-deployment-platform-v2

git status --short
git branch --show-current

git fetch origin main
git merge --ff-only origin/main

make test
make lint
```

Sau đó health các site quan trọng:

```bash
platform-v2 deploy health <site1>
platform-v2 deploy health <site2>
```

Không update Platform production bằng random ZIP/copy nếu Git checkout đang là source-of-truth.

---

## 30. `.env` update workflow nhanh

Nếu chỉ sửa biến Laravel thông thường, không đổi Docker ports/topology/container secret:

```bash
platform-v2 deploy optimize <site>
platform-v2 deploy health <site>
```

Interactive:

```text
Deploy & Runtime
→ Backend / Laravel Runtime
→ Optimize / Reload .env
→ Health
```

Không cần Full Deploy chỉ để reload config thông thường.

Nếu đổi:

```text
HTTP_PORT
SOCKET_PORT
DB container secret
Redis server password/container environment
compose service topology
Dockerfile/image dependencies
```

thì cân nhắc Full Deploy/recreate theo contract.

---

## 31. Health expectations

Deploy Health PASS phải chứng minh application thật hoạt động:

```text
[OK] service db
[OK] service redis
[OK] service app
[OK] service web
[OK] workers
[OK] Laravel boot
[OK] Application HTTP: 2xx/3xx
[OK] Deploy health OK.
```

Container health alone không đủ.

### 500

Check Laravel exception/config/session/database.

### 502

Check host/local request, web container log, DNS `app`, app:9000, FastCGI upstream; stale web upstream sau app restart là failure pattern đã từng xảy ra.

---

## 32. Monitoring / routine operations

Hàng ngày/tuần:

```bash
platform-v2 site list
docker ps
df -h
docker system df
nginx -t
```

Định kỳ:

```bash
make test
make lint
certbot renew --dry-run
```

Backup verify theo policy.

Có thể dùng external monitoring cho HTTPS status, disk, load, memory, certificate expiry và backup age.

---

## 33. VPS migration checklist

Khi chuyển Platform sang VPS mới, không chỉ clone code.

Cần đánh giá/migrate riêng:

```text
[ ] Platform repository/main
[ ] Inventory state
[ ] Laravel source directories
[ ] each site .env
[ ] Docker named volumes / database data
[ ] storage uploads
[ ] backup repository
[ ] Nginx site configs
[ ] Certbot certificates/account state hoặc re-issue certificates
[ ] GitHub SSH private keys + config (secure transfer)
[ ] DNS records
[ ] reserved ports/resources
```

Không copy `/var/lib/docker` live giữa hosts như một generic migration method. Dùng backup/restore/data export strategy phù hợp.

---

## 34. Disaster recovery minimal assets

Để dựng lại hoàn toàn VPS cần giữ off-server:

1. Git repositories.
2. Verified site backups (database + storage + source khi cần).
3. Inventory export/snapshot.
4. Secure record của DNS/domain configuration.
5. SSH/GitHub access recovery plan.
6. `INFORMATION.md` + guide này.

TLS certificates có thể re-issue nếu DNS/control còn, nên TLS private key backup không phải lúc nào cũng bắt buộc; nếu backup thì phải bảo vệ như secret.

---

## 35. Fresh VPS acceptance test

Một VPS mới chỉ nên được coi ready khi tất cả pass:

```text
[ ] Ubuntu LTS updated
[ ] clock/timezone correct
[ ] Docker Engine + Compose plugin active
[ ] docker hello-world pass
[ ] Nginx active + nginx -t pass
[ ] Certbot command available
[ ] GitHub owner SSH identity pass
[ ] Platform repository cloned from correct owner
[ ] platform-v2 symlink points correct repo
[ ] make test = 0
[ ] make lint = 0
[ ] Inventory valid
[ ] first test/staging site create/deploy pass
[ ] Laravel boot pass
[ ] local HTTP 2xx/3xx
[ ] public HTTPS pass
[ ] backup create + verify pass
```

---

## 36. Recommended order for a completely new server

```text
1. Install Ubuntu 24.04 LTS
2. Update OS + timezone
3. Install base tools
4. Install Docker CE + Compose plugin
5. Install Nginx + Certbot
6. Configure firewall
7. Configure GitHub SSH owner identities
8. Clone tungocvan/laravel-deployment-platform-v2
9. Install/symlink platform-v2
10. Run make test + make lint
11. Validate Inventory baseline
12. Configure DNS for staging/test domain
13. Create first site through Platform
14. Deploy health
15. SSL verify
16. Backup + verify
17. Only then onboard production sites
```

---

## 37. Official references for version verification

Trước khi dựng VPS mới trong tương lai, verify latest supported releases tại:

```text
Ubuntu release/support:
https://ubuntu.com/about/release-cycle

Docker Engine Ubuntu:
https://docs.docker.com/engine/install/ubuntu/

Node release schedule:
https://nodejs.org/en/about/previous-releases

PHP supported versions:
https://www.php.net/supported-versions.php

MariaDB releases:
https://mariadb.org/

Redis releases:
https://redis.io/
```

Guide này cố ý khuyến nghị stable/LTS line thay vì pin mọi package host vào một patch version cố định. Patch pinning chỉ nên dùng khi tổ chức có maintenance/reproducibility policy rõ ràng.

---

## 38. Final recommendation

Đối với production VPS mới, baseline thực dụng nhất hiện tại:

```text
Ubuntu Server 24.04 LTS
Docker Engine official stable (29.x line hiện tại) + Compose v2 plugin
Nginx host 1.24+
Certbot 2.9+
Git 2.43+
Bash 5.2+
Python 3.12+
OpenSSH 9.6+
```

Application runtime tiếp tục do Dockerfile của từng Laravel repository quyết định; không cài PHP/Node/MariaDB/Redis host chỉ vì application container dùng chúng.

Sau mọi thay đổi infrastructure lớn, định nghĩa “đã xong” luôn là:

```text
Platform regression pass
+ lint pass
+ Docker services healthy
+ Laravel boot pass
+ Application HTTP pass
+ public HTTPS pass
+ verified backup available
```
