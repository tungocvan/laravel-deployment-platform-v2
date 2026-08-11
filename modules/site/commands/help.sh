#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
cat <<'EOF'
USAGE
  platform site <command> [options]

COMMANDS
  list
  show <name|domain|path>
  exec <site> <command...>
  doctor <site>
  create --name=... --domain=... --repo=... [options]
  update <site> [--dry-run] [--yes] [--timeout=N]
  production-seed <site>
  change-domain <site> --domain=<new-domain> [--dry-run] [--yes] [--no-ssl]
  repair-ssl <site>
  duplicate --from=... --name=... --domain=... [options]

UPDATE
  Đồng bộ chính xác site về origin/<branch>, deploy lại runtime, migrate, chạy
  Production Seed allow-list, optimize/health check và cập nhật commit Inventory.
  Không chạy DatabaseSeeder hoặc db:seed toàn bộ.

PRODUCTION SEED
  Đồng bộ metadata production-safe được allow-list. Hiện tại gồm:
  Modules\Role\database\seeders\RolesAndPermissionsSeeder
  sau đó chạy permission:cache-reset. Nếu seeder không tồn tại thì bỏ qua an toàn.

CHANGE DOMAIN
  Đổi domain của managed site nhưng giữ nguyên code, database, storage, path và ports.
  Domain mới được preflight + tạo Nginx/SSL trước; chỉ sau khi runtime healthy mới
  cập nhật APP_URL/Inventory và remove Nginx domain cũ. Certificate cũ được giữ lại.

REPAIR SSL
  Repair SSL cho domain hiện tại của managed site. Nếu certificate đã tồn tại,
  Platform re-attach certificate vào Nginx; nếu chưa có thì issue certificate mới.

LIFECYCLE
  disable <site> [--yes]
  enable <site> [--yes]
  maintenance on <site>
  maintenance off <site>
  lifecycle <site>

ARCHIVE
  archive <site> [--dry-run] [--yes]
  restore-archive <site> [--yes]
  archives

PURGE
  purge <site> [options]
      Permanent resource destruction.

PURGE OPTIONS
  --dry-run
  --yes
  --keep-source
  --keep-volumes
  --keep-ssl
  --no-backup      # dangerous, requires --yes

RECOMMENDED
  site update <site> --dry-run
  site update <site>
  site production-seed <site>
  site change-domain <site> --domain=<new-domain> --dry-run
  site repair-ssl <site>
  site archive <site>
  site purge <site> --dry-run
EOF
