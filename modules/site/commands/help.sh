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
  change-domain <site> --domain=<new-domain> [--dry-run] [--yes] [--no-ssl]
  duplicate --from=... --name=... --domain=... [options]

UPDATE
  Fast-forward site từ origin/<branch>, deploy lại runtime, migrate, optimize,
  health check và cập nhật commit trong Inventory. Update không chạy db:seed.
  Working tree có local changes hoặc Git history diverged sẽ bị từ chối.

CHANGE DOMAIN
  Đổi domain của managed site nhưng giữ nguyên code, database, storage, path và ports.
  Domain mới được preflight + tạo Nginx/SSL trước; chỉ sau khi runtime healthy mới
  cập nhật APP_URL/Inventory và remove Nginx domain cũ. Certificate cũ được giữ lại.

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
  site change-domain <site> --domain=<new-domain> --dry-run
  site archive <site>
  site purge <site> --dry-run
  site purge <site>
EOF
