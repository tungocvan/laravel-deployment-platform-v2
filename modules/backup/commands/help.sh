#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform backup <command> [options]

COMMANDS
  create <site> [--no-source] [--no-database] [--no-storage]
  list [site]
  show <site> <backup-id>
  verify <site> <backup-id>
  prune <site> --keep=<count>

  restore <site> <backup-id|latest> [options]
      Restore snapshot về site hiện tại hoặc provision thành site mới.

RESTORE OPTIONS
  --domain=<domain>
      Rebind APP_URL/Nginx/SSL sang domain khác.

  --database=<database>
      Restore vào database khác.

  --as=<new-site>
      Restore snapshot thành site mới.
      Khi dùng --as, bắt buộc --domain mới.

  --path=<path>
      Path cho site mới. Default: /opt/projects/<new-site>.

  --http-port=<port|auto>
  --socket-port=<port|auto>
      Dùng cho --as. Default: auto.

  --source-only
  --database-only
  --storage-only

  --no-emergency-backup
      Không backup site hiện tại trước restore.

  --no-ssl
      Không issue/verify SSL.

  --skip-dns-check
      Bỏ kiểm tra DNS resolve.

  --overwrite-database
      Cho phép import vào database đích đã tồn tại trong restore-as-new.

  --dry-run
      Chỉ preflight, không thay đổi hệ thống.

  --yes
      Không hỏi xác nhận.

EXAMPLES
  sudo platform backup restore nvh-test latest --dry-run

  sudo platform backup restore nvh-test latest

  sudo platform backup restore nvh-test latest \
    --domain=demo.tungocvan.com \
    --database=db_demo \
    --dry-run

  sudo platform backup restore nvh-test latest \
    --as=nvh-recovery \
    --domain=recovery.tungocvan.com \
    --database=db_nvh_recovery \
    --dry-run
EOF
