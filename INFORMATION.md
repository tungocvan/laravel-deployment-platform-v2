# Laravel Deployment Platform v2 — INFORMATION / AI & Developer Handoff

> Tài liệu này là điểm bắt đầu ưu tiên cho AI mới, tài khoản ChatGPT/Codex mới, developer mới hoặc người vận hành mới tiếp nhận `laravel-deployment-platform-v2` trên VPS. Mục tiêu là giúp người tiếp nhận hiểu đúng repository, kiến trúc, runtime, quy tắc an toàn, workflow Git/Deploy/Site, cách test và cách tiếp tục phát triển mà không cần biết toàn bộ lịch sử hội thoại trước đây.

**Cập nhật theo trạng thái repository ngày 2026-08-21.** Khi tài liệu này mâu thuẫn với source code mới hơn, ưu tiên source code và tests hiện tại.

---

## 1. Project identity — đọc phần này trước tiên

| Thuộc tính | Giá trị hiện tại |
|---|---|
| Repository chính | `tungocvan/laravel-deployment-platform-v2` |
| GitHub URL | `https://github.com/tungocvan/laravel-deployment-platform-v2` |
| SSH canonical | `git@github.com:tungocvan/laravel-deployment-platform-v2.git` |
| SSH alias thường dùng trên VPS hiện tại | `git@github-tungocvan:tungocvan/laravel-deployment-platform-v2.git` |
| Default branch / production source | `main` |
| Version file | `VERSION` — hiện vẫn là `2.0.0-dev` |
| Product direction | Platform 2.1 stabilization / production hardening |
| Runtime install path mặc định | `/opt/laravel-deployment-platform-v2` |
| Managed projects root mặc định | `/opt/projects` |
| CLI chính | `platform-v2` |
| Legacy CLI khác trên VPS | có thể tồn tại command `platform`; **không được nhầm với Platform v2** |
| Inventory mặc định | `/opt/laravel-deployment-platform-v2/state/sites.json` |
| Primary implementation language | Bash; Python nhỏ cho JSON/state operations |
| Application runtime | Laravel applications chạy bằng Docker Compose |
| Host reverse proxy | Nginx |
| TLS | Certbot / Let's Encrypt |

### Cảnh báo về tài liệu lịch sử

Một số tài liệu cũ có thể còn nhắc repository `vhdtshop-ux/laravel-deployment-platform-v2`. Repository đang được phát triển và vận hành hiện tại là:

```text
tungocvan/laravel-deployment-platform-v2
```

Không tự động đổi repository/remote dựa trên tài liệu cũ. Luôn kiểm tra:

```bash
git remote -v
git branch --show-current
git log -3 --oneline --decorate
```

---

## 2. Mục tiêu của Platform

Laravel Deployment Platform v2 là một lớp orchestration CLI/module cho nhiều website Laravel trên một hoặc nhiều VPS.

Platform **không thay thế** Laravel, Docker, Git, Nginx, Certbot hay MariaDB/Redis. Platform chuẩn hóa cách các thành phần đó được vận hành theo lifecycle có kiểm tra, dry-run, health gate, backup, rollback và Inventory.

Mental model:

```text
Operator / AI / Interactive UI / Automation
                  |
                  v
          /usr/local/bin/platform-v2
                  |
                  v
              bin/platform
                  |
       +----------+-----------+
       |                      |
       v                      v
Interactive UI          core dispatcher
       |                      |
       v                      v
modules/ui/...      modules/<module>/commands
                              |
                              v
                    modules/<module>/lib
                              |
                              v
               Docker / Git / Laravel / Nginx /
               Certbot / filesystem / database
```

Platform có hai cách sử dụng song song:

```bash
# Interactive UI
platform-v2
platform-v2 menu

# CLI/module API
platform-v2 site list
platform-v2 deploy health <site>
platform-v2 backup create <site>
platform-v2 git sync-repositories ...
```

**Không dùng:**

```bash
platform-v2 0
```

`0` chỉ có ý nghĩa khi đang ở trong Interactive UI. Nếu truyền trực tiếp, dispatcher hiểu `0` là tên module và báo `CORE.MODULE_NOT_FOUND`.

---

## 3. Source-of-truth order

Khi tiếp nhận task hoặc debug, dùng thứ tự ưu tiên sau:

1. `modules/*/lib/*.sh` và `modules/*/commands/*.sh` — implementation thực tế.
2. Tests tương ứng của module.
3. `docs/specification/*` nếu có.
4. `docs/runbooks/*` và ADR/architecture notes.
5. `INFORMATION.md` và `docs/AI-HANDOFF.md`.
6. `README.md`, `ROADMAP.md`, lịch sử hội thoại.

Lý do: Platform phát triển nhanh, một số tài liệu lịch sử có thể chưa được đồng bộ ngay sau mỗi PR.

---

## 4. Repository structure

```text
laravel-deployment-platform-v2/
├── bin/
│   └── platform                 # entry point
├── core/                        # bootstrap, dispatcher, helpers chung
├── config/                      # platform config/schema/examples
├── modules/                     # business modules
├── docs/                        # specs, runbooks, architecture, handoff
├── templates/                   # templates khi có
├── tests/                       # core/module integration tests
├── tools/                       # lint/tooling
├── state/                       # runtime state; KHÔNG commit production state
├── install.sh                   # install Platform vào /opt + symlink platform-v2
├── Makefile                     # regression entry points
├── VERSION
└── README.md
```

Module contract tổng quát:

```text
modules/<module>/
├── commands/    # CLI entry handlers
├── lib/         # business logic/helpers
├── docs/        # module docs nếu có
└── tests/       # module regression tests
```

Nguyên tắc ownership:

- `core/` không nên chứa business logic riêng của Site/Deploy/Backup/etc.
- UI không được copy lại business logic; UI thu input, giải thích, confirm và gọi module command/helper.
- Logic Git phải được gom trong Git module/helper khi có thể.
- Logic Docker/Laravel deployment thuộc Deploy module.
- SSL thuộc SSL module; Nginx thuộc Nginx module.

---

## 5. Module map hiện tại

Các module chính trong source hiện tại:

| Module | Trách nhiệm |
|---|---|
| `backup` | Tạo/list/show/verify/prune/restore backup |
| `database` | status/shell/export/import/backup/restore database |
| `deploy` | build/up/migrate/optimize/health/status/frontend/runtime lifecycle |
| `doctor` | diagnostics/read-only preflight |
| `git` | verify repo, remote migration, bootstrap repo, sync repositories |
| `inventory` | index managed sites + sync/validate/reservations |
| `lifecycle` | enable/disable/maintenance/archive/restore lifecycle |
| `nginx` | render/enable/disable/verify/conflict/remove Nginx config |
| `package` | install/upgrade/list/show/verify/history package |
| `plugin` | plugin lifecycle |
| `purge` | destructive cleanup |
| `site` | create/show/list/duplicate/doctor/provision/orchestration |
| `ssl` | issue/list/show/verify/renew/remove Certbot certificates |
| `ui` | Interactive Operations Console |

Để xác minh source hiện tại thay vì dựa trên tài liệu:

```bash
ls -1 /opt/laravel-deployment-platform-v2/modules
platform-v2 modules 2>/dev/null || true
```

---

## 6. Runtime paths và configuration

Các default quan trọng từ `config/platform.env.example`:

```text
PLATFORM_HOME=/opt/laravel-deployment-platform-v2
PROJECTS_ROOT=/opt/projects
DOCKER_PLATFORM_DIR=/opt/laravel-docker-platform
INVENTORY_FILE=/opt/laravel-deployment-platform-v2/state/sites.json
PLATFORM_DEFAULT_SITE_REPO=git@github.com:tungocvan/laravel-shop.git
START_HTTP_PORT=8081
START_SOCKET_PORT=6001
```

Managed site thông thường:

```text
/opt/projects/<site>
```

Nhưng **không được hardcode path**. Inventory có thể chứa site ở path khác, ví dụ site lịch sử có thể không nằm dưới `/opt/projects`. Luôn lấy path từ Inventory:

```bash
platform-v2 site list
platform-v2 site show <site>
```

Inventory record thường chứa:

```json
{
  "name": "example",
  "domain": "example.com",
  "path": "/opt/projects/example",
  "http_port": 8081,
  "socket_port": 6001,
  "database": "db_example",
  "status": "active",
  "repo": "git@github.com:owner/repo.git",
  "branch": "main",
  "commit": "...",
  "type": "laravel",
  "managed": true
}
```

Inventory là managed-resource index, không phải database nghiệp vụ của Laravel.

---

## 7. Interactive UI / Operations Console

Chạy:

```bash
platform-v2
# hoặc
platform-v2 menu
```

Top-level menu hiện được tổ chức theo mục đích:

```text
1) Sites & Repository
2) Backup & Restore
3) Deploy & Runtime
4) Doctor & Domain Diagnostics
5) Infrastructure — SSL & Nginx
6) Packages
7) Hướng dẫn sử dụng / Chọn đúng chức năng
0) Exit
```

Menu được thiết kế để operator nhìn thấy chức năng con trước khi vào submenu.

### Repository Management trong Sites

Các workflow quan trọng:

```text
15) Update kho mới (main cùng dòng source)
16) Khởi tạo kho mới trống/tái tạo target từ kho cũ
17) Đồng bộ 2 kho Git
18) Kiểm tra quyền repository / SSH key
```

Menu 18 kiểm tra quyền bằng:

```text
READ   -> git ls-remote
WRITE  -> push temporary refs/platform/write-probe/...
DELETE -> delete đúng temporary probe ref
```

Không được dùng probe để sửa `main` hoặc tag.

Nếu canonical `git@github.com:owner/repo.git` không có write permission, flow sẽ thử SSH alias hiện có phù hợp owner (ví dụ `github-tungocvan`) trước khi đề nghị tạo key mới. Điều này tránh kết luận sai khi server có nhiều GitHub identity.

Nếu phải tạo key:

- filename chứa owner + repository để tránh trùng;
- nếu file đã tồn tại, thêm timestamp;
- tạo dedicated SSH Host alias;
- chỉ hiển thị `.pub` public key;
- **không bao giờ cat/private key**;
- Platform không thể tự cấp permission trên GitHub nếu chưa có API/admin permission; operator phải thêm public key vào GitHub account hoặc Deploy Keys.

---

## 8. Git identity / SSH model

Một VPS có thể dùng nhiều GitHub account/key. Không giả định `git@github.com` luôn authenticate đúng owner.

Ví dụ:

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_ed25519
    IdentitiesOnly yes

Host github-tungocvan
    HostName github.com
    User git
    IdentityFile /root/.ssh/github_tungocvan_ed25519
    IdentitiesOnly yes
```

Khi debug permission:

```bash
ssh -T git@github.com
ssh -T git@github-tungocvan
```

Để test repo owner `tungocvan` bằng đúng alias:

```bash
git ls-remote git@github-tungocvan:tungocvan/laravel-deployment-platform-v2.git HEAD
```

Write/delete test phải dùng ref tạm:

```bash
git push git@github-tungocvan:tungocvan/laravel-deployment-platform-v2.git \
  HEAD:refs/platform/write-probe/manual-test

git push git@github-tungocvan:tungocvan/laravel-deployment-platform-v2.git \
  :refs/platform/write-probe/manual-test
```

Không test permission bằng cách push vào `main`.

---

## 9. Repository comparison rule — rất quan trọng

Khi so sánh kho cũ và kho mới, **remote repository main là authoritative**, không dùng project local làm source-of-truth.

Lý do: local project có thể chưa fetch/pull commit mới nhất hoặc có working tree dirty.

Quy tắc:

```text
old remote/main
      vs
new remote/main
```

Không phải:

```text
local project HEAD/worktree
      vs
new remote
```

Local site được dùng để biết identity/HEAD và để đảm bảo cutover an toàn, nhưng data cần copy/sync giữa repository phải lấy từ repository remote.

---

## 10. Git workflow: Update repository address

Use case: đổi remote của site sang repository mới nhưng repository mới đã chứa cùng history/main lineage.

Safety contract:

```text
site branch phải phù hợp contract (thường main)
fetch old/main trực tiếp từ old repository
fetch new/main trực tiếp từ new repository
verify old/main là ancestor của new/main
không lấy local dirty source làm chuẩn
chỉ đổi origin sau verify
sync Inventory sau thành công
```

Nếu lineage không tương thích: BLOCK.

Không tự merge, không force-push để làm cho hai history “trông giống nhau”.

---

## 11. Git workflow: Bootstrap/replace repository

Use case: chuyển old repository/main sang repository đích mới.

Workflow an toàn hiện đã được phát triển theo hướng:

```text
read old repository/main directly
→ inspect target
→ verify write/delete with temporary ref
→ copy/replace target main theo contract
→ verify exact commit SHA
→ verify exact Git tree
→ only then change site origin
→ inventory sync
```

Nếu target có dữ liệu, flow replace phải có confirmation và sử dụng safety/backup ref + force-with-lease theo implementation hiện tại. Không dùng blind force push.

Site local dirty changes phải được preserve; repository remote/main mới là source authoritative cho bootstrap.

---

## 12. Git workflow: Sync two repositories

Contract:

```text
SOURCE/main -> TARGET/main
```

Quy tắc:

- Target empty: có thể sync.
- Target equal source: no-op.
- Target behind source: fast-forward target.
- Target ahead: BLOCK.
- Diverged: BLOCK.
- Không force push.
- Không auto merge.
- Không sync ngược.
- Không thay site origin/Inventory.
- Không deploy/database/container.

Dry-run phải hiển thị relation, commit count và file changes trước khi operator đồng ý.

---

## 13. Site provisioning model

Create Site / Duplicate / Restore-as-new cần dùng shared provisioning engine, không tự triển khai lại từng infrastructure step riêng biệt.

Mental pipeline:

```text
validate new identity
→ allocate path/ports/database
→ clone/configure source
→ generate site .env + Docker identity
→ deploy prepare/build/up
→ migrate/optimize
→ nginx
→ ssl
→ health
→ commit/sync Inventory cuối cùng
```

Safety principles:

- Inventory active record là bước cuối sau khi provision thành công.
- Failure giữa pipeline phải cleanup/rollback target resources phù hợp.
- Domain/port/database conflict phải được phát hiện trước mutation lớn.

### Session identity reset khi Create Site

Một lỗi production đã được phát hiện: source repository có thể mang `.env` template/cached values của domain cũ như:

```text
SESSION_COOKIE=
SESSION_DOMAIN=old-domain.example
SESSION_SECURE_COOKIE=
```

Điều này có thể làm Laravel HTTP 500 dù containers healthy.

Provisioning hiện phải reset session identity cho site mới, bao gồm logic tương đương:

```text
SESSION_COOKIE=<site>-session
SESSION_DOMAIN=<new-domain hoặc giá trị policy hiện tại>
SESSION_SECURE_COOKIE=true khi HTTPS
```

Không cho site mới kế thừa session identity của site nguồn/template cũ.

---

## 14. Deploy engine

Full Deploy mental contract:

```text
01 preflight / identity
02 Docker build
03 Docker up
04 wait database
05 Laravel migrate --force
06 Laravel optimize
07 runtime/application health
```

### Khi nào dùng Full Deploy

Dùng Full Deploy khi thay đổi có thể ảnh hưởng:

- Dockerfile/image;
- Composer dependencies copied vào image;
- frontend build stage;
- migrations;
- compose/services;
- DB/Redis container secrets hoặc ports;
- application source cần rebuild image.

Full Deploy có thể tốn thời gian vì build nhiều images.

### Khi chỉ sửa `.env` thông thường

Không cần Full Deploy nếu chỉ thêm/sửa config ứng dụng không làm thay đổi Docker topology/port/service secret.

UI path:

```text
Deploy & Runtime
→ Backend / Laravel Runtime
→ Optimize / Reload .env
→ Health
```

CLI:

```bash
platform-v2 deploy optimize <site>
platform-v2 deploy health <site>
```

---

## 15. Deploy optimize / runtime refresh

Một production bug quan trọng đã được fix: Laravel config cache có thể được refresh nhưng PHP-FPM cũ vẫn giữ runtime/opcache/config behavior; container `healthy` không đảm bảo application request thành công.

Optimize/runtime refresh hiện phải đảm bảo lifecycle tương đương:

```text
Laravel optimize:clear
→ config:cache
→ route:cache (có thể warning theo contract)
→ view:cache
→ restart PHP runtime: app + queue + queue-admission-documents + scheduler
→ wait app healthy
→ restart web
→ wait web healthy
```

### Tại sao phải restart `web`

Đã gặp production case:

```text
restart app
→ app container IP thay đổi / FastCGI upstream lifecycle thay đổi
→ Nginx web container giữ upstream cũ
→ HTTP 502
```

Restart web sau app refresh giải quyết upstream stale state.

---

## 16. Deploy health gate — container healthy chưa đủ

Một nguyên tắc cốt lõi Platform 2.1:

> Deploy không được báo SUCCESS chỉ vì Docker containers healthy.

Health hiện cần kiểm tra tối thiểu:

```text
db service
redis service
app service
web service
queue worker
queue-admission-documents worker (nếu project có)
scheduler worker
Laravel boot (`php artisan about` hoặc equivalent)
Application HTTP local
```

Application HTTP chỉ chấp nhận `2xx/3xx` theo runtime gate hiện tại.

Ví dụ PASS:

```text
[OK] Laravel boot
[OK] Application HTTP: 200 (http://127.0.0.1:<port>/)
[OK] Deploy health OK.
```

Ví dụ FAIL:

```text
[ERROR] Application HTTP: 500 (...)
[ERROR] Application HTTP verification failed; deploy không được đánh dấu thành công.
```

Hoặc:

```text
Application HTTP: 502
```

Không bypass health gate chỉ để có chữ SUCCESS.

---

## 17. Known production failure patterns đã gặp

### 17.1 HTTP 500 — empty/old session cookie/domain

Symptoms:

```text
Laravel boot = OK
Docker services = healthy
HTTP = 500
```

Possible resolved config:

```text
session.cookie=''
session.domain='old-domain.example'
session.secure=''
```

Fix principle:

- correct `.env` session identity;
- clear/cache config;
- restart PHP runtime;
- restart web;
- health gate.

### 17.2 HTTP 502 sau restart app

Symptoms:

```text
app healthy
web healthy
Laravel boot OK
HTTP 502
```

Nếu restart web làm HTTP `502 -> 200`, nguyên nhân thường là stale FastCGI upstream/container lifecycle.

Platform runtime refresh đã được harden để restart web sau PHP runtime.

### 17.3 Route cache duplicate name

Example:

```text
Unable to prepare route [website/logout] for serialization.
Another route has already been assigned name [logout].
```

Hiện route cache failure có thể là WARN tùy deploy contract, nhưng source Laravel nên được sửa duplicate route names để production `route:cache` sạch.

---

## 18. Docker identity — không được fallback `laravel-app`

Multi-site VPS đặc biệt nhạy với `COMPOSE_PROJECT_NAME`.

Nếu chạy `docker compose` từ sai context hoặc không resolve identity đúng, Docker có thể tạo accidental project:

```text
laravel-app-app-1
laravel-app-queue-1
...
```

trong khi site thật là:

```text
<site>-app-1
<site>-web-1
...
```

Do đó:

- Platform phải resolve Compose project từ site identity / `.docker-platform.env` / Inventory contract.
- Khi debug bằng tay, dùng đúng project directory và project name.
- Không assume directory name == Compose project name nếu source cho phép override.

Useful checks:

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker inspect <container> --format '{{ index .Config.Labels "com.docker.compose.project" }}'
```

---

## 19. Application Docker model thường gặp

Các Laravel repository được Platform quản lý có thể dùng Docker multi-stage tương tự:

```text
composer-deps
frontend-build
socket-deps
app (php-fpm)
socket (node)
web (nginx)
```

Compose thường có:

```text
app
queue
queue-admission-documents
scheduler
socket
web
db
redis
```

Runtime versions là trách nhiệm của application repository/Dockerfile, không phải host Platform. Ví dụ source hiện từng dùng:

```text
PHP 8.3
Node 22
Composer 2.8
MariaDB 11.8
Redis 7.4-alpine
Nginx 1.28-alpine
```

Không tự nâng major version Docker image trong Platform repo nếu chưa test application source.

---

## 20. Nginx / SSL model

Host Nginx là external reverse proxy tới local published HTTP port của từng Docker site.

Concept:

```text
Internet :443
   |
Host Nginx + Certbot
   |
127.0.0.1:<site-http-port>
   |
Docker web container
   |
FastCGI app:9000
```

Nginx module chịu trách nhiệm render/enable/disable/verify/conflict/remove config.

SSL module centralizes Certbot. Site module không nên copy direct Certbot business logic.

Khi Cloudflare proxy được dùng, DNS/HTTP-01 behavior phải được xem xét; không kết luận DNS sai chỉ vì domain resolve ra Cloudflare IP.

---

## 21. Backup / restore / lifecycle safety

Backup phải được verify trước khi được coi là safety point.

Lifecycle reversible:

```text
active <-> maintenance
active <-> disabled
active -> archived -> active
```

Archive không đồng nghĩa purge.

Recommended destructive workflow:

```text
backup + verify
→ archive hoặc dry-run
→ inspect
→ purge khi thật sự muốn xóa vĩnh viễn
```

Purge là irreversible. Không bypass typed confirmation/safety checks chỉ vì operator nói “xóa nhanh”.

---

## 22. Development workflow chuẩn cho AI/developer

### 22.1 Không phát triển trực tiếp trên production `main`

Trước khi code:

```bash
cd /opt/laravel-deployment-platform-v2
git fetch origin main
git status --short
git branch --show-current
git log -3 --oneline --decorate
```

Tạo feature branch hoặc worktree riêng.

### 22.2 Worktree test pattern

```bash
git fetch origin <feature-branch>
TEST_DIR="$(mktemp -d /tmp/platform-v2-feature.XXXXXX)"
git worktree add --detach "$TEST_DIR" "origin/<feature-branch>"
```

Chạy tests trong worktree, production tree phải giữ nguyên.

### 22.3 Test contract

Minimum trước merge:

```bash
cd "$TEST_DIR"
make test
make lint
```

`Makefile` hiện chạy các nhóm:

```text
core
transaction
audit
package
lifecycle
modules
git
deploy
doctor
site
ui
```

Một số audit negative-path test cố ý tạo warning khi không thể ghi path `/proc/...`; warning đó không nhất thiết là failure nếu test cuối trả `[OK]` và exit 0.

### 22.4 Production real-world dry-run

Với workflow Git/Deploy quan trọng, ngoài unit/regression nên có read-only/dry-run trên site thật khi phù hợp.

Ví dụ:

```bash
INVENTORY_FILE=/opt/laravel-deployment-platform-v2/state/sites.json \
PLATFORM_HOME="$TEST_DIR" \
"$TEST_DIR/bin/platform" deploy health <site>
```

Không mutate production từ test branch nếu chưa có explicit approval.

---

## 23. PR / merge discipline

Recommended:

```text
feature branch
→ tests
→ lint
→ real dry-run/health nếu cần
→ PR
→ review
→ merge main
→ production fast-forward
→ regression/health
```

Production update:

```bash
cd /opt/laravel-deployment-platform-v2
git fetch origin main
git merge --ff-only origin/main
make test
make lint
```

Không dùng `git reset --hard` trên production tree nếu chưa xác minh local state và chưa có lý do rõ ràng.

---

## 24. AI handoff protocol — AI mới nên làm gì trong 10 phút đầu

1. Đọc `INFORMATION.md`.
2. Đọc `README.md` và `docs/AI-HANDOFF.md` để biết lịch sử, nhưng nhớ owner trong tài liệu cũ có thể outdated.
3. Kiểm tra repo thật:

```bash
cd /opt/laravel-deployment-platform-v2
git remote -v
git branch --show-current
git log -10 --oneline --decorate
```

4. Kiểm tra Platform:

```bash
platform-v2 --help
platform-v2
```

5. Kiểm tra Inventory:

```bash
platform-v2 site list
```

6. Trước task cụ thể, đọc module implementation + tests liên quan.
7. Không dựa vào project local để kết luận remote repository history.
8. Không tạo SSH key mới trước khi thử identity/alias hiện có.
9. Không báo deploy success nếu HTTP gate fail.
10. Mọi thay đổi lớn: branch + tests + lint + PR.

---

## 25. Commands thường dùng

```bash
# UI
platform-v2
platform-v2 menu

# Site
platform-v2 site list
platform-v2 site show <site>
platform-v2 site doctor <site>

# Deploy
platform-v2 deploy health <site>
platform-v2 deploy optimize <site>
platform-v2 deploy run <site>
platform-v2 deploy status <site>

# Backup
platform-v2 backup list <site>
platform-v2 backup create <site>

# Tests
make test
make lint

# Git identity diagnostics
ssh -T git@github.com
ssh -T git@github-tungocvan
```

Command syntax có thể phát triển. Luôn chạy `--help` hoặc đọc `modules/<module>/commands` trước khi automation.

---

## 26. Security rules

Không commit hoặc paste vào AI/chat:

- private SSH keys;
- `.env` secrets;
- database passwords;
- Redis password;
- API tokens;
- TLS private keys;
- production database dumps nếu không cần thiết.

Public SSH key `.pub` có thể hiển thị/chia sẻ để cài vào GitHub.

Repository access probe chỉ dùng temporary ref và phải cleanup ref đó.

SSH private key generated by menu 18 phải chmod `600` và không được in ra terminal.

---

## 27. Known technical debt / things to keep watching

- `VERSION` vẫn là `2.0.0-dev` dù product đang được gọi Platform 2.1 trong vận hành; cần quyết định release/versioning chính thức.
- Một số historical docs có owner/repo cũ.
- Route cache warning do duplicate route names là application-level debt và nên được sửa trong Laravel source.
- UI và CLI command naming cần tiếp tục giữ backward compatibility khi có automation/scripts ngoài Platform.
- Docker/Compose identity phải tiếp tục được test trên multi-site hosts.
- `healthy` container không thể thay cho real Laravel/HTTP health.
- Repository access phải nhận biết multi-account SSH identity.

---

## 28. Definition of Done cho thay đổi Platform

Một feature/fix chỉ nên coi là hoàn tất khi:

```text
[ ] behavior contract rõ
[ ] không hardcode site/domain/port/secret cụ thể
[ ] implementation nằm đúng module
[ ] dry-run/confirmation nếu mutation nguy hiểm
[ ] regression test mới hoặc cập nhật test hiện có
[ ] make test = 0
[ ] make lint = 0
[ ] production runtime không bị chạm trong test PR
[ ] real health/dry-run pass nếu feature liên quan runtime
[ ] PR merge vào main
[ ] production fast-forward main
[ ] post-update health pass
```

---

## 29. Tài liệu liên quan

- `README.md` — overview ngắn.
- `docs/AI-HANDOFF.md` — handoff lịch sử/kiến trúc sâu, nhưng cần đối chiếu INFORMATION.md/source mới.
- `ROADMAP.md` — roadmap lịch sử.
- `docs/specification/` — behavior contracts nếu có.
- `docs/runbooks/` — operator runbooks nếu có.
- `docs/VPS-DEPLOYMENT-GUIDE.md` — triển khai Platform trên VPS Ubuntu mới.

---

## 30. Final rule for future AI/developer

Đừng cố “sửa nhanh cho chạy” bằng cách bypass safety.

Platform này được xây dựng để biến những thao tác dễ gây lỗi production — repository migration, deploy, Docker identity, backup/restore, Nginx/SSL, SSH permission — thành workflow có kiểm tra và rollback/health gate.

Khi thêm feature mới, ưu tiên:

```text
correctness
→ safety
→ observable output
→ dry-run/testability
→ operator usability
→ performance
```

Nếu cần chọn giữa “deploy báo thành công” và “deploy fail đúng vì HTTP 500/502”, luôn chọn fail đúng.