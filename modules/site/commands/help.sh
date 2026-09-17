#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
cat <<'EOF'
USAGE
  platform site <command> [options]

PRODUCTION OPERATIONS
  create --name=... --domain=... [--repo=...] [options]
  update <site> [--dry-run] [--migrate] [--yes]
  env <site> <env-file> [--dry-run] [--yes]
  diagnostics <site>
  artisan <site> <artisan-command...>
  runtime <site>
  cleanup <site> [--apply] [--yes]

INSPECTION
  list
  show <name|domain|path>
  exec <site> <command...>
  doctor <site>
  duplicate --from=... --name=... --domain=... [options]

UPDATE SAFETY
  - Working tree phải sạch; không git clean/reset tự động.
  - Git update chỉ fast-forward.
  - Migration mới bị BLOCK nếu không truyền --migrate.
  - --migrate tạo verified backup trước khi chạy migrate --force.
  - Build chỉ chạy khi change classification yêu cầu.

ENV SAFETY
  - Preview chỉ hiển thị key names; không in secret values.
  - Runtime reconcile dùng Compose up --no-build khi cần.
  - Health fail sẽ khôi phục .env checkpoint.

CREATE OPTIONS
  --repo=<git-url>        default: git@github.com:tungocvan/laravel-shop.git
                          override: PLATFORM_DEFAULT_SITE_REPO
  --branch=<branch>       default: main
  --path=<absolute-path>  default: /opt/projects/<site>
  --http-port=<port|auto>
  --socket-port=<port|auto>
  --no-ssl
  --no-build
  --dry-run
  --yes

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
  purge <archived-site> [options]
  purge <active-site> --force-active --yes

PURGE OPTIONS
  --dry-run
  --yes
  --force-active
  --keep-source
  --keep-volumes
  --keep-ssl
  --no-backup

EXAMPLES
  platform site update demo --dry-run
  platform site update demo --migrate --yes
  platform site diagnostics demo
  platform site artisan demo about
  platform site runtime demo
  platform site cleanup demo
EOF
