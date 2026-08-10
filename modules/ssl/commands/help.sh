#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform ssl <command> [options]

COMMANDS
  issue <domain>
      Issue/deploy certificate via Certbot Nginx plugin.

  repair <domain>
      Repair SSL deployment. Reuse an existing certificate when present,
      re-attach it to the matching Nginx vhost, or issue a new certificate.

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
  sudo platform ssl repair nvh.tungocvan.com
  platform ssl show nvh.tungocvan.com
  sudo platform ssl verify nvh.tungocvan.com
EOF
