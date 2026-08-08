#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform ssl <command> [options]

COMMANDS
  issue <domain>
      Issue/deploy certificate via Certbot Nginx plugin.

  show <domain>
      Show certificate metadata.

  verify <domain>
      Verify certificate exists and files are readable.

  renew <domain>
      Renew certificate for domain.

  remove <domain>
      Delete Certbot certificate after confirmation.

  list
      List Certbot certificates.

EXAMPLES
  sudo platform ssl issue nvh.tungocvan.com
  platform ssl show nvh.tungocvan.com
  sudo platform ssl verify nvh.tungocvan.com
EOF
