# Laravel Deployment Platform v2

Laravel Deployment Platform v2 là nền tảng CLI dạng module để quản lý nhiều website Laravel chạy bằng Docker trên một hoặc nhiều VPS.

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

## Nguyên tắc

- Mỗi module tự chứa command, library, docs và tests.
- `core/` chỉ chứa logic dùng chung.
- Runtime state không được commit.
- Không hardcode domain, port hoặc secret.
- Destructive command phải có confirmation.
- Mọi deploy phải có health gate.

## Trạng thái

Đây là **Modular Starter Kit**, dùng để hợp nhất code production v1 theo từng module. Không thay trực tiếp bản đang chạy trước khi migration và test hoàn tất.
