# Laravel Deployment Platform v2 — AI Handoff / Project Map

> Mục tiêu của tài liệu này là giúp một AI mới, một chat mới, một tài khoản khác, Codex hoặc một developer mới hiểu nhanh trạng thái thực tế của dự án và tiếp tục công việc mà không phải tái dựng toàn bộ lịch sử trao đổi.

## 1. Project identity

| Thuộc tính | Giá trị |
|---|---|
| Repository | `vhdtshop-ux/laravel-deployment-platform-v2` |
| Default branch | `main` |
| Baseline commit ban đầu | `67ba5e9` — `chore: establish Platform 2.0 baseline` |
| Platform version file | `VERSION` = `2.0.0-dev` |
| Runtime path mặc định | `/opt/laravel-deployment-platform-v2` |
| Managed Laravel projects | thông thường nằm dưới `/opt/projects/<site>` |
| Ngôn ngữ triển khai chính | Bash + Python nhỏ cho JSON/atomic state operations |
| Runtime application model | Laravel applications chạy bằng Docker Compose |
| Reverse proxy | Nginx trên host |
| TLS | Certbot / Let's Encrypt |
| State policy | Runtime state, secrets và backup không commit vào Git |

## 2. Project purpose

Laravel Deployment Platform v2 là một CLI module hóa để quản lý nhiều website Laravel chạy bằng Docker trên một VPS hoặc nhiều VPS.

Mục tiêu không phải là thay thế Docker/Laravel/Nginx mà là điều phối chúng theo một lifecycle chuẩn, có preflight, backup, health gate, rollback/transaction ở các khu vực phù hợp và giao diện CLI/UI nhất quán.

Mental model:

```text
Operator / Interactive UI / Automation
                |
                v
          bin/platform
                |
                v
        core/dispatcher.sh
                |
                v
 modules/<module>/commands/<command>.sh
                |
                v
      modules/<module>/lib/*.sh
                |
                v
 Docker / Laravel / Nginx / Certbot / Git / filesystem
```

## 3. Source-of-truth order

Khi các tài liệu mâu thuẫn nhau, dùng thứ tự ưu tiên sau:

1. Code thực tế trong `modules/*/lib` và `modules/*/commands`.
2. `docs/specification/*` mới nhất liên quan chức năng đó.
3. Tests của module.
4. Runbook.
5. README/ROADMAP tổng quát.

Lý do: `README.md` và `ROADMAP.md` hiện vẫn còn một số mô tả từ giai đoạn starter kit, trong khi source đã có nhiều module và workflow mới hơn.

## 4. Architectural principles — không được phá vỡ nếu không có quyết định kiến trúc rõ ràng

| Nguyên tắc | Ý nghĩa |
|---|---|
| Core không chứa business logic | `core/` chỉ xử lý bootstrap, dispatcher, module system, config, lock, helper chung |
| Business logic thuộc module | Site, Deploy, Backup, SSL, Nginx... tự chịu trách nhiệm nghiệp vụ của mình |
| UI là frontend, không copy business logic | UI chỉ chọn input, preview, confirm và gọi CLI/module API |
| Specification trước implementation | Thay đổi lớn cần cập nhật spec hoặc ít nhất làm rõ contract trước |
| Inventory không phải database nghiệp vụ | Inventory là index/cache của managed resources và có validation/sync |
| Destructive operation phải an toàn | Backup/verify/confirmation trước thao tác phá hủy khi có thể |
| Inventory commit cho site mới là bước cuối | Không ghi site active trước khi provision thành công |
| Deploy phải có health gate | Không coi deploy thành công nếu health chưa đạt |
| Package upgrade mang tính transactional | Version/package record chỉ commit sau verify thành công |
| Không hardcode domain/port/secret | Identity phải đến từ Inventory, config hoặc argument |
| Runtime state không commit | State, secret, backup, `.env`, key/cert không đưa vào Git |
| Reuse helper/module API | Không copy cùng một logic sang nhiều module |

## 5. Repository structure

| Path | Vai trò |
|---|---|
| `bin/platform` | Entry point; không có argument hoặc `menu`/`ui` thì mở Interactive UI; các command khác đi qua dispatcher |
| `core/` | Bootstrap, dispatcher và shared core helpers |
| `modules/` | Toàn bộ business modules |
| `docs/specification/` | Contract/behavior specification |
| `docs/runbooks/` | Hướng dẫn vận hành |
| `docs/adr/` | Architectural Decision Records |
| `docs/architecture/` | Architecture notes |
| `templates/` | Template module và Nginx |
| `packages/` | Package repository placeholders/cache paths; runtime package state không commit |
| `tests/` | Core/module-level tests |
| `tools/` | Tooling như lint |
| `config/` | Schema và platform env example |
| `.github/` | CI, issue templates, PR template |

Mỗi module theo contract cơ bản:

```text
modules/<name>/
├── commands/
├── lib/
├── docs/
└── tests/
```

## 6. Module map

| Module | Trách nhiệm chính | Command/API đáng chú ý |
|---|---|---|
| `site` | Quản lý site và orchestration lifecycle | `list`, `show`, `exec`, `doctor`, `duplicate`, `enable`, `disable`, `maintenance`, `archive`, `restore-archive`, `archives`, `purge`, `rename`, `create/register/remove` |
| `deploy` | Docker/Laravel deployment lifecycle và frontend build | `run`, `prepare`, `identity`, `migrate`, `optimize`, `health`, `status`, `frontend detect/scripts/install/build`, history/rollback support |
| `database` | Database operational commands | `status`, `shell`, `export`, `import`, `backup`, `restore`; import/restore phải backup trước |
| `inventory` | Managed Laravel site index + reserved external resources | `list`, `show`, `validate`, `sync`, `repair`, `reserve`, `reserved`, `unreserve` |
| `git` | Git repository validation/normalization | `branch`, `commit`, `info`, `remote`, `trust`, `verify`, `normalize`; Git-consuming modules nên dùng `platform_git_verify` |
| `backup` | Snapshot source/database/storage và restore engine | `create`, `list`, `show`, `verify`, `prune`, `restore` |
| `nginx` | Nginx managed-site lifecycle | `render`, `enable`, `disable`, `ensure`, `show`, `conflicts`, `verify`, `remove` |
| `ssl` | Certbot/Let's Encrypt lifecycle | `issue`, `show`, `verify`, `renew`, `remove`, `list`, `status` |
| `doctor` | Read-only diagnostics / preflight | `domain`, `site`, `platform`, `run`; domain preflight hỗ trợ proposed identity |
| `package` | Cài/nâng cấp package và lịch sử | `install`, `upgrade`, `list`, `show`, `verify`, `history` |
| `plugin` | Plugin lifecycle | `install`, `list`, `enable`, `disable`, `remove` |
| `lifecycle` | Reversible site lifecycle implementation | active/maintenance/disabled/archive/restore archive logic |
| `purge` | Irreversible resource destruction | permanent cleanup sau backup safety |
| `ui` | Interactive Bash frontend | main menu, Site, Backup/Restore, Deploy Wizard, Doctor, Infrastructure, Packages |

## 7. Core dispatcher behavior

`bin/platform` có hai lớp routing:

```text
platform-v2
platform-v2 menu
platform-v2 ui
    -> modules/ui/commands/menu.sh

platform-v2 <module> <command> ...
    -> core/bootstrap.sh
    -> platform_dispatch
    -> module_dispatch
    -> modules/<module>/commands/<command>.sh
```

`module_dispatch` chỉ execute command script nếu module tồn tại và handler executable.

## 8. Inventory model

Inventory dành cho Laravel applications do Platform quản lý. External resources không được giả làm Laravel site mà nằm trong `reserved_resources`.

Port được xem là đã sử dụng nếu xuất hiện trong một trong các nguồn:

- Laravel managed sites.
- Reserved external resources.
- Host listeners (`ss -lnt`).
- Docker published ports.

Typical managed site identity cần các dữ liệu như:

```text
name
domain
path
database
http_port
socket_port
compose_project_name
repo / branch / commit (khi có)
```

Inventory phải được validate sau mutation. Đối với provision site mới, Inventory commit là bước cuối cùng.

## 9. Site Provisioning Engine

Create, Duplicate và Restore-as-new không được tự implement lại Deploy/Nginx/SSL lifecycle.

Shared target pipeline:

```text
configure target
→ deploy prepare
→ strategy-specific data phase
→ deploy finalize
→ nginx
→ ssl
→ health
→ inventory commit
```

Điểm cốt lõi:

- Provision target identity trước.
- Data strategy khác nhau tùy create/duplicate/restore.
- Shared infrastructure stages phải tái sử dụng cùng engine/helper.
- Failure trước Inventory commit phải rollback target resources phù hợp.

## 10. Deploy engine

Full deploy contract:

```text
ensure Docker identity
→ preflight
→ Docker build
→ Docker up
→ wait database
→ Laravel migrate --force
→ Laravel optimize
→ health check
```

Laravel optimize hiện gồm:

```text
optimize:clear với cache array an toàn
config:cache
route:cache (warning nếu fail)
view:cache (warning nếu fail)
```

Health gate kiểm tra tối thiểu:

```text
db
redis
app
web
Laravel CLI
```

Docker identity không được để template fallback `laravel-app` trên multi-site host.

## 11. Frontend build strategy

Frontend là trách nhiệm của Deploy Module, không phải UI.

Detection priority:

```text
Dockerfile có stage `AS frontend-build`
    -> strategy = docker-multistage
không có
    -> host package manager fallback
```

### Docker multi-stage

Đây là strategy ưu tiên cho project đang dùng Dockerfile kiểu:

```dockerfile
FROM node:22-bookworm-slim AS frontend-build
RUN npm ci
RUN npm run build
```

Frontend-only build:

```text
docker compose build app web
→ docker compose up -d app web
→ deploy health
```

Không rebuild `queue`, `scheduler`, `socket`, `db`, `redis` trong frontend-only flow.

Node/npm bên trong Docker build stage là source of truth. Host Node/npm không cần thiết khi strategy là docker-multistage.

### Host fallback

Nếu không có Docker frontend stage:

- Detect `pnpm-lock.yaml` -> pnpm.
- Detect `yarn.lock` -> yarn.
- Còn lại -> npm.
- Có thể install dependencies rồi chạy `build` script.
- Với Vite, verify `public/build/manifest.json`.

## 12. Backup model

Backup snapshot có thể chứa:

```text
source.tar.gz
database.sql.gz
storage.tar.gz
manifest.json
checksums
```

Backup phải có verify checksum trước khi được coi là hợp lệ.

Common commands:

```bash
platform-v2 backup create <site>
platform-v2 backup list <site>
platform-v2 backup show <site> <backup-id>
platform-v2 backup verify <site> <backup-id>
platform-v2 backup restore <site> <backup-id|latest> ...
```

## 13. Restore engine

### Restore existing site

```text
verify backup
→ preflight
→ emergency backup
→ restore source/database/storage
→ configure identity
→ deploy
→ nginx/ssl nếu identity thay đổi
→ health
→ inventory sync
```

### Restore as new site

```text
verify backup
→ preflight new identity
→ extract snapshot
→ Site Provisioning Engine
→ import database/storage
→ nginx
→ ssl
→ health
→ Inventory commit
```

Important options:

```text
--domain
--database
--as
--path
--http-port=<port|auto>
--socket-port=<port|auto>
--source-only
--database-only
--storage-only
--no-emergency-backup
--no-ssl
--skip-dns-check
--overwrite-database
--dry-run
--yes
```

DNS resolve thành công là yêu cầu mặc định. Cloudflare proxy có thể resolve ra Cloudflare IP, vì vậy origin IP equality không phải điều kiện mặc định.

## 14. Lifecycle model

Lifecycle reversible:

```text
active ↔ maintenance
active ↔ disabled
active → archived → active
```

Archive là safe detach, không phải delete:

```text
backup + verify
→ nginx disable
→ docker compose down (keep volumes)
→ preserve source
→ preserve SSL
→ remove active Inventory record
→ write archive record
```

`restore-archive` khôi phục archived site về active lifecycle.

## 15. Purge model

Purge chịu trách nhiệm irreversible destruction:

```text
backup safety
→ nginx disable
→ docker down -v
→ nginx config removal
→ ssl removal
→ source removal
→ inventory/archive removal
→ purge history
```

Safety rule quan trọng:

```text
Source auto-delete chỉ được phép mặc định bên dưới /opt/projects/*
```

Recommended operator workflow:

```text
archive
→ inspect/dry-run purge
→ purge
```

## 16. Nginx model

Managed Nginx flow:

```text
render domain/http-port
→ enable symlink
→ nginx -t
→ reload
```

Key commands:

```text
render
enable
disable
ensure
show
conflicts
verify
remove
```

`conflicts <domain>` dùng để phát hiện nhiều config cùng khai báo `server_name`.

## 17. SSL model

SSL Module centralizes Certbot; Site Module không nên gọi Certbot trực tiếp.

Issue contract:

```text
validate domain
→ require Nginx config
→ certbot --nginx
→ verify certificate files
```

Remove contract:

```text
validate domain
→ ensure certificate exists
→ refuse nếu enabled Nginx còn reference certificate
→ certbot delete
```

Cloudflare note: HTTP-01 có thể fail nếu DNS record còn Proxied hoặc có duplicate DNS record. UI hiện có SSL Wizard để hỗ trợ create/verify/retry mà không cần rebuild/restore lại site.

## 18. Doctor / preflight

`doctor domain` là read-only.

Đối với domain mới, mục tiêu là đánh giá readiness cho Provision/Restore-as-new.

Đối với existing managed domain, Doctor có thể report:

```text
site name
database
project path
HTTP port
Socket port
backup count
latest backup ID
timestamp
latest verify/checksum status
```

Doctor không nên mutation tài nguyên.

Important conceptual distinction:

- `doctor domain` cho new-site readiness có thể báo conflict nếu domain đã thuộc Inventory/Nginx.
- Điều đó không có nghĩa existing domain không thể thực hiện SSL maintenance; SSL Wizard có workflow riêng.

## 19. Package Manager

Transactional upgrade contract:

```text
1. Validate ZIP/checksum/manifest.
2. Load current package record.
3. Backup every payload target file.
4. Run candidate installer in transaction mode.
5. Run candidate verify.
6. Commit record/history only after verify succeeds.
7. On failure: restore files + restore old record.
```

Rule:

```text
Package version MUST NOT advance after failed verify.
```

Đây là cơ chế delivery chính cho thay đổi Platform lớn trên production VPS.

## 20. Interactive UI philosophy

Interactive UI là lớp sử dụng chính cho operator không muốn nhớ nhiều câu lệnh, nhưng CLI vẫn là API cho automation và debug.

Entry points:

```bash
sudo platform-v2
sudo platform-v2 menu
sudo platform-v2 ui
```

Current UI groups:

```text
Sites
Backup / Restore
Deploy
Doctor
Infrastructure (Nginx / SSL)
Packages
```

UI rules:

- Không chạy trực tiếp Docker/Nginx/Certbot/npm nếu module API đã tồn tại.
- Chọn site từ Inventory khi có thể.
- Destructive action cần preview/dry-run và confirmation.
- Restore có persisted pending state để resume.
- SSL Wizard là task-oriented: nhập domain -> Inventory/Nginx/runtime/SSL -> issue/verify/retry.
- Deploy Wizard detect project capability rồi gọi Deploy Module.

## 21. Resume Restore UI state

Restore UI lưu pending operation vào runtime state, ví dụ:

```text
state/ui/restore-last.json
```

State chứa các trường như:

```text
mode
source_site
backup
target_site
domain
database
ssl_mode
status
updated_at
```

Behavior:

```text
before execute -> save pending state
failure        -> mark failed, keep state
success        -> clear state
resume         -> load state, run dry-run again, re-check SSL/DNS, confirm, execute
```

Runtime state directory bị `.gitignore`, vì vậy file này không có trong repository.

## 22. Runtime data intentionally NOT in Git

`.gitignore` loại các nhóm sau:

```text
.env / .env.* (trừ example)
*.key
*.pem
*.log
*.tmp
*.pid
/tmp/
/cache/
*.tar
*.tar.gz
*.zip
/backups/
/state/
/runtime/
*.bak
```

Do đó repository không thể tự cho biết:

- Site nào đang active trên VPS hiện tại.
- Current Inventory JSON runtime.
- Installed package records/version history.
- Real backup files.
- Certbot certificates/private keys.
- Docker volumes/current containers.
- Secret `.env` values.

AI/developer phải yêu cầu runtime evidence từ VPS khi câu hỏi phụ thuộc các dữ liệu này.

## 23. Typical host dependencies / external contracts

Platform code hiện giả định hoặc tích hợp với:

```text
bash
python3
Docker daemon
Docker Compose plugin/wrapper
Nginx
Certbot
Git
jq ở một số tác vụ/debug operator
Laravel Docker Platform wrapper tại /opt/laravel-docker-platform (Deploy Module)
```

Deploy Module dùng compose wrapper/preflight từ Docker platform thay vì gọi `docker compose` raw ở mọi nơi.

## 24. Testing / verification workflow

Trước khi coi một thay đổi hoàn tất:

```text
bash -n changed shell files
module tests
tools/lint.sh nếu phù hợp
package verify
runtime dry-run
runtime functional test trên VPS
health check
```

Các thao tác destructive phải test `--dry-run` trước nếu command hỗ trợ.

## 25. Development / operator workflow recommended for future AI

Khi tiếp nhận dự án ở chat mới:

1. Đọc `docs/AI-HANDOFF.md`.
2. Đọc `git log --oneline -20` để biết thay đổi mới nhất.
3. Đọc `VERSION`.
4. Đọc spec/module source liên quan task; không dựa riêng vào README.
5. Search function/command trong repo trước khi đề xuất code.
6. Xác định module owner của nghiệp vụ trước khi sửa.
7. Không copy business logic sang UI.
8. Nếu cần thay đổi production, ưu tiên đóng gói qua Package Manager.
9. Yêu cầu user chạy runtime test trên VPS khi cần Docker/Nginx/Certbot/database thực tế.
10. Dựa trên output runtime để kết luận; không suy đoán state bị `.gitignore`.

## 26. Rules for changing code

Trước mỗi thay đổi, trả lời 5 câu hỏi:

```text
1. Module nào sở hữu responsibility này?
2. Có helper/API hiện có để reuse không?
3. Có phá backward compatibility không?
4. Failure có rollback/cleanup rõ ràng không?
5. Có test/dry-run/verify chứng minh behavior không?
```

Không nên:

```text
- thêm command mới chỉ vì UI cần một nút
- chạy Docker/Nginx/Certbot trực tiếp trong UI
- mutate Inventory trước khi target health pass
- commit secrets/runtime state
- xóa source ngoài managed path mà không explicit safety gate
- coi README cũ là source of truth khi source/spec mới nói khác
```

## 27. Platform 2.0 -> Platform 2.1 direction

Platform 2.0 đã đạt mức feature-complete cho lifecycle cốt lõi. Hướng 2.1 là stabilization và usability, không phải tăng số command vô hạn.

Các mục tiêu đã được định hướng:

```text
- Interactive Menu / task-oriented wizard dễ dùng
- CLI/output chuẩn hóa
- Error code chuẩn hóa
- Transaction framework dùng chung
- Rollback framework rõ ràng
- Audit log thống nhất
- Integration tests end-to-end
- Doctor/preflight mạnh hơn
- Documentation/release discipline
- giảm duplicate logic / technical debt
```

Priority hiện tại: giữ engine CLI/module làm backend ổn định, UI chỉ là client task-oriented của các API đó.

## 28. Known documentation / consistency debt at baseline

Các điểm cần AI mới biết ngay:

1. `README.md` liệt kê ít module hơn source thực tế.
2. `ROADMAP.md` vẫn mô tả nhiều mục như tương lai trong khi source đã triển khai thêm nhiều workflow.
3. `core/dispatcher.sh` help text có danh sách module tĩnh và có thể không phản ánh đủ module discovered thực tế.
4. `VERSION` vẫn là `2.0.0-dev`; package/module source có revision chi tiết hơn.
5. Một vài spec version header có thể chậm hơn code thực tế; khi nghi ngờ, đọc command/lib/test.
6. Runtime installed package versions nằm trong state và không có trong Git.

Không tự ý sửa các điểm này cùng một feature khác nếu không có scope rõ ràng; nên xử lý thành documentation/core cleanup riêng.

## 29. Critical workflows summary

| Task | Preferred flow |
|---|---|
| New site | Site Provisioning Engine -> Deploy -> Nginx -> SSL -> Health -> Inventory commit |
| Duplicate | Reuse provisioning/restore-style engine; không copy Deploy/Nginx/SSL logic |
| Backup | Source + DB + storage -> manifest/checksum -> verify |
| Restore existing | Verify -> preflight -> emergency backup -> restore -> deploy -> health -> sync |
| Restore new | Verify -> new identity preflight -> provisioning engine -> data import -> infra -> health -> commit |
| Disable | Reversible lifecycle action; giữ data |
| Maintenance | Reversible Laravel/site maintenance state |
| Archive | Backup+verify -> disable Nginx -> Docker down keep volumes -> detach Inventory -> archived metadata |
| Restore archive | Archived -> active, reuse preserved resources/metadata |
| Purge | Backup safety -> destroy runtime resources -> remove source/SSL/config/state -> purge history |
| SSL create | Nginx exists -> `ssl issue` -> verify; không rebuild site |
| Frontend build | Detect strategy; Docker multi-stage ưu tiên -> build/recreate `app web` -> health |
| Package upgrade | Validate -> backup targets -> install candidate -> verify -> commit or rollback |

## 30. Quick command reference

```bash
# Open UI
sudo platform-v2

# Discover modules
platform-v2 modules

# Inventory
platform-v2 inventory list
platform-v2 inventory validate

# Site
platform-v2 site list
platform-v2 site show <site>
platform-v2 site doctor <site>

# Deploy
platform-v2 deploy status <site>
platform-v2 deploy health <site>
sudo platform-v2 deploy run <site>
sudo platform-v2 deploy frontend build <site>

# Backup
sudo platform-v2 backup create <site>
platform-v2 backup list <site>
sudo platform-v2 backup verify <site> <backup-id>
sudo platform-v2 backup restore <site> latest --dry-run

# Nginx
sudo platform-v2 nginx verify
platform-v2 nginx conflicts <domain>

# SSL
platform-v2 ssl list
sudo platform-v2 ssl verify <domain>
sudo platform-v2 ssl issue <domain>

# Doctor
sudo platform-v2 doctor domain <domain>

# Packages
platform-v2 package list
platform-v2 package verify <Package-ID>
```

## 31. First instruction for any new AI

Nếu bạn là AI mới tiếp nhận repository này:

> Không bắt đầu bằng cách đề xuất rewrite. Hãy đọc source và spec liên quan trước. Xác định module owner, reuse API hiện có, giữ backward compatibility, yêu cầu runtime evidence khi cần, và coi UI là client của CLI/module engine. Platform đã được test thực tế trên VPS; mục tiêu tiếp theo là chuẩn hóa, giảm technical debt và tăng độ tin cậy chứ không phải thay toàn bộ kiến trúc.

---

Tài liệu này phải được cập nhật khi có thay đổi kiến trúc/lifecycle lớn để luôn đóng vai trò canonical handoff cho developer/AI mới.