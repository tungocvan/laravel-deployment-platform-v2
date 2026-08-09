# Laravel Deployment Platform v2

Laravel Deployment Platform v2 là nền tảng CLI dạng module để quản lý nhiều website Laravel chạy bằng Docker trên một hoặc nhiều VPS.

## AI / Developer Handoff

Nếu tiếp nhận dự án ở chat mới, tài khoản khác, Codex hoặc AI khác, hãy đọc trước:

- [`docs/AI-HANDOFF.md`](docs/AI-HANDOFF.md) — bản đồ kiến trúc, module ownership, workflow, safety rules, runtime boundaries, technical debt và hướng Platform 2.1.

Khi tài liệu tổng quát mâu thuẫn với source mới hơn, ưu tiên source/module implementation và specification liên quan theo thứ tự được mô tả trong AI Handoff.

## Mục tiêu

```bash
platform site list
platform site create ...
platform deploy nvh
platform database nvh backup
platform inventory sync nvh
platform doctor
```

## Kiến trúc

```text
bin/platform
    ↓
core/dispatcher.sh
    ↓
modules/<module>/commands/<command>.sh
    ↓
modules/<module>/lib/*.sh
    ↓
core/lib/*.sh
```

## Module hiện có

- `site`
- `deploy`
- `database`
- `inventory`
- `ssl`
- `doctor`
- `plugin`

> Lưu ý: danh sách trên là mô tả lịch sử rút gọn. Xem `docs/AI-HANDOFF.md` hoặc chạy `platform-v2 modules` để lấy module map đầy đủ từ source/runtime hiện tại.

## Nguyên tắc

- Mỗi module tự chứa command, library, docs và tests.
- `core/` chỉ chứa logic dùng chung.
- Runtime state không được commit.
- Không hardcode domain, port hoặc secret.
- Destructive command phải có confirmation.
- Mọi deploy phải có health gate.

## Trạng thái

Repository này chứa baseline modular Platform đang tiếp tục được hoàn thiện theo hướng Platform 2.1: stabilization, task-oriented UI, chuẩn hóa framework dùng chung, integration tests và production hardening.
