#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform doctor <command> [options]

COMMANDS
  site <site>
      Kiểm tra managed site hiện hữu: Inventory/path/Git metadata,
      Docker critical services, worker health và backup status.

  domain <domain> [options]
      Kiểm tra domain/identity có sẵn sàng để provision hoặc restore-as-new.

OPTIONS FOR domain
  --name=<site-name>
      Kiểm tra site name và project path dự kiến.

  --database=<database>
      Kiểm tra database có đang thuộc Inventory site khác hay không.

  --path=<path>
      Kiểm tra target path cụ thể.
      Nếu có --name nhưng không có --path:
      /opt/projects/<name>

  --http-port=<port|auto>
      Default: auto. Chỉ kiểm tra, không reserve.

  --socket-port=<port|auto>
      Default: auto. Chỉ kiểm tra, không reserve.

  --skip-dns-check
      Bỏ DNS lookup.

EXAMPLES
  sudo platform doctor site tnv

  sudo platform doctor domain ntd.tungocvan.com

  sudo platform doctor domain ntd.tungocvan.com \
    --name=ntd-test \
    --database=db_ntd_test
EOF
