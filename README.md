# Laravel Deployment Platform v2

Laravel Deployment Platform v2 là nền tảng CLI dạng module để quản lý nhiều website Laravel chạy bằng Docker trên một hoặc nhiều VPS.

## AI / Developer Handoff

Nếu tiếp nhận dự án ở chat mới, tài khoản khác, Codex hoặc AI/developer khác, hãy đọc theo thứ tự:

1. [`INFORMATION.md`](INFORMATION.md) — **handoff ưu tiên hiện tại**: repository identity chính xác, kiến trúc, module map, Git/SSH model, Site/Deploy lifecycle, các lỗi production đã gặp, safety rules, development/PR workflow và checklist để AI mới tiếp tục phát triển.
2. [`docs/VPS-DEPLOYMENT-GUIDE.md`](docs/VPS-DEPLOYMENT-GUIDE.md) — dựng VPS Ubuntu mới từ đầu: dependency host, version khuyến nghị, Docker/Nginx/Certbot, GitHub SSH, install Platform, tests, security, backup và acceptance checklist.
3. [`docs/AI-HANDOFF.md`](docs/AI-HANDOFF.md) — tài liệu kiến trúc/lịch sử chi tiết bổ sung; một số identity lịch sử có thể cũ nên phải đối chiếu `INFORMATION.md` và source hiện tại.

Khi tài liệu mâu thuẫn với source mới hơn, ưu tiên source/module implementation và tests hiện tại.

## Mục tiêu

```bash
platform-v2 site list
platform-v2 site create ...
platform-v2 deploy health <site>
platform-v2 backup create <site>
platform-v2 inventory sync <site>
platform-v2
```

## Kiến trúc

```text
bin/platform
    ↓
core/dispatcher.sh / Interactive UI
    ↓
modules/<module>/commands/<command>.sh
    ↓
modules/<module>/lib/*.sh
    ↓
Docker / Laravel / Git / Nginx / Certbot / filesystem
```

## Module hiện có

Các module thực tế hiện gồm các nhóm như `site`, `deploy`, `database`, `inventory`, `git`, `backup`, `nginx`, `ssl`, `doctor`, `package`, `plugin`, `lifecycle`, `purge`, `ui`.

> Xem `INFORMATION.md` hoặc trực tiếp thư mục `modules/` để lấy module map đúng source hiện tại.

## Nguyên tắc

- Mỗi module tự chứa command, library, docs và tests.
- `core/` chỉ chứa logic dùng chung.
- Runtime state không được commit.
- Không hardcode domain, port hoặc secret.
- Destructive command phải có confirmation/safety contract.
- Repository comparison/sync phải dùng remote repository source-of-truth, không dựa vào local project stale/dirty.
- Docker identity phải đúng từng site; không fallback accidental `laravel-app` trên multi-site VPS.
- Mọi deploy phải có health gate: container healthy chưa đủ, Laravel boot và Application HTTP phải pass.

## Trạng thái

Repository này đang được hoàn thiện theo hướng Platform 2.1: production hardening, task-oriented UI, repository safety, multi-identity SSH, runtime HTTP health gate, integration tests và operator usability.
