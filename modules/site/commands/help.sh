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
  duplicate --from=... --name=... --domain=... [options]

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
      Permanent resource destruction for archived sites.

  purge <active-site> --force-active --yes
      Purge an active site directly without archiving first.
      Backup safety remains enabled unless --no-backup is explicitly used.

PURGE OPTIONS
  --dry-run
  --yes
  --force-active   # required when source state is active inventory
  --keep-source
  --keep-volumes
  --keep-ssl
  --no-backup      # dangerous, requires --yes

RECOMMENDED
  site archive <site>
  site purge <site> --dry-run
  site purge <site> --yes

FORCE ACTIVE
  site purge <site> --force-active --dry-run
  site purge <site> --force-active --yes
EOF
