#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform package <command>

COMMANDS
  install <zip>       Cài package mới
  upgrade <zip>       Nâng package đã cài (transactional)
  list                Danh sách package
  show <id>           Xem package record
  verify <id>         Kiểm tra package
  history <id>        Xem lịch sử
EOF
