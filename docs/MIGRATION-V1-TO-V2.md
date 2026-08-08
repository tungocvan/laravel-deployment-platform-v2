# Migration v1 → v2

## Không ghi đè production trực tiếp

1. Backup `/opt/laravel-deployment-platform`.
2. Giải nén v2 vào staging.
3. Chạy migration script ở chế độ dry-run.
4. Copy code nghiệp vụ v1 vào đúng module.
5. Chạy lint và tests.
6. Chuyển symlink chỉ sau khi xác nhận.

## Mapping

```text
commands/site/*.sh   → modules/site/commands/
commands/build.sh    → modules/deploy/commands/run.sh
commands/db.sh       → modules/database/
commands/doctor.sh   → modules/doctor/
lib/inventory.sh     → modules/inventory/lib/
lib/render-nginx.sh  → modules/site/lib/ hoặc core integration
```
