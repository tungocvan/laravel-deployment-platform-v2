#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform nginx <command> [options]

COMMANDS
  render <domain> <http-port>
      Render/update config in sites-available.

  enable <domain>
      Enable site symlink, verify nginx, reload.

  disable <domain>
      Disable site symlink, verify nginx, reload.

  ensure <domain> <http-port>
      Render + enable + verify + reload.

  show <domain>
      Show current config.

  conflicts <domain>
      Find configs declaring this server_name.

  verify
      nginx -t

  remove <domain>
      Disable and remove managed config after backup.

EXAMPLES
  sudo platform nginx ensure nvh.tungocvan.com 8084
  sudo platform nginx conflicts nvh.tungocvan.com
EOF
