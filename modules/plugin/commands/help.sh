#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform plugin <list|install|remove|enable|disable>
EOF
