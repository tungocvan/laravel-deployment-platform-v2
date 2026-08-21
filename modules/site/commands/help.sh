#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"
cat <<'EOF'
USAGE
  platform site <command> [options]

COMMANDS
  create --name=... --domain=... --repo=... [options]
  list
  show <name|domain|path>
  exec <site> <command...>
  doctor <site>
  duplicate --from=... --name=... --domain=... [options]

CREATE OPTIONS
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

EXAMPLES
  site create --name=demo --domain=demo.example.com --repo=git@github.com:org/app.git --dry-run
  site create --name=demo --domain=demo.example.com --repo=git@github.com:org/app.git --yes

RECOMMENDED
  site archive <site>
  site purge <site> --dry-run
  site purge <site> --yes

FORCE ACTIVE
  site purge <site> --force-active --dry-run
  site purge <site> --force-active --yes
EOF
