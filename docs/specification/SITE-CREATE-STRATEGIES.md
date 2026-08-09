# Site Create Runtime Strategies

## Mục tiêu

Chuẩn hóa `platform-v2 site create` để tạo Laravel site từ Git repository theo nhiều runtime strategy mà không phá các site hiện tại.

## Strategies

### `platform`

Dùng Laravel Docker Platform/runtime hiện tại. Đây là mặc định tương thích ngược cho site cũ và flow hiện có.

### `repository`

Repository chịu trách nhiệm Docker runtime. Platform clone repository, validate Docker contract, cấu hình site identity/runtime values, build/start stack, finalize Laravel, cấu hình Nginx/SSL và commit Inventory.

Repository strategy tối thiểu cần cung cấp:

- Laravel 12 project hợp lệ.
- Dockerfile hợp lệ.
- Compose file (`compose.yaml` mặc định, có thể chỉ định file khác).
- Service/runtime contract đủ để Platform chạy stack và health check.

### `auto`

- Có Dockerfile + Compose contract hợp lệ: chọn `repository`.
- Không có contract repository: fallback `platform`.

Auto detection phải được hiển thị trong dry-run trước khi thực thi.

## CLI contract

```bash
platform-v2 site create \
  --name=<name> \
  --domain=<domain> \
  --repo=<git-repository> \
  --branch=main \
  --docker=platform|repository|auto \
  [--dockerfile=Dockerfile] \
  [--compose-file=compose.yaml] \
  [--no-ssl] \
  [--dry-run] \
  [--yes]
```

`--docker=platform` là default để giữ backward compatibility.

## Inventory contract

Site mới lưu thêm metadata:

```json
{
  "runtime_strategy": "platform|repository",
  "dockerfile": "Dockerfile",
  "compose_file": "compose.yaml"
}
```

Site cũ không có `runtime_strategy` được hiểu là `platform`.

## Create flow

1. Validate input.
2. Validate Inventory conflicts.
3. Allocate ports/database/path.
4. Clone repository và checkout branch.
5. Resolve runtime strategy.
6. Validate Laravel + Docker contract.
7. Preview/dry-run.
8. Configure environment/runtime identity.
9. Build/start runtime theo strategy.
10. Wait dependencies.
11. Laravel finalize: migrate, runtime filesystem, optimize, health.
12. Configure Nginx/SSL.
13. Commit Inventory metadata.
14. Emit audit outcome.

Create failure phải rollback các resource đã tạo theo transaction framework; không được làm thay đổi site đang tồn tại.

## UI contract

Menu `platform-v2` > `SITE MANAGEMENT` bổ sung `Create site`.

Create flow hỏi strategy:

1. Docker Platform hiện tại
2. Docker theo repository
3. Auto detect
0. Back

UI chỉ orchestration CLI contract; không chứa business logic riêng. Trước mutation phải hiển thị dry-run/preview và yêu cầu xác nhận.

## Safety / compatibility

- Không migrate site cũ sang repository strategy tự động.
- Không sửa runtime của site đang active khi create site mới.
- Không ghi secret vào Inventory/audit.
- Repository strategy phải fail-fast nếu Docker contract thiếu hoặc không hợp lệ.
- Dry-run không clone/build/start/mutate Inventory.

## Test gates

- Strategy resolution: platform/repository/auto.
- Missing Dockerfile/Compose contract.
- Existing name/domain/path/port conflict.
- Dry-run không mutation.
- Create failure rollback.
- Inventory metadata compatibility.
- UI menu/argument mapping.
- Existing duplicate/restore/lifecycle regression.
