#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform inventory <command> [options]

COMMANDS
  list
      Liệt kê Laravel sites.

  show <name|domain|path>
      Xem một Laravel site.

  validate
      Kiểm tra inventory.

  sync <name|domain|path> [--path=/opt/project] [--name=name]
      Sync Laravel runtime metadata.

  repair <name|domain|path>
      Re-sync Laravel metadata, không tự thay port.

  reserve --name=<name> --http-port=<port> [options]
      Ghi nhận external resource để giữ port.
      Nếu cùng name đang nằm trong sites, tự chuyển ra reserved_resources.

  reserved
      Liệt kê reserved resources.

  unreserve <name>
      Xóa reserved resource.

OPTIONS FOR reserve
  --name=<name>                 Bắt buộc
  --http-port=<port>            Bắt buộc
  --application=<type>          Ví dụ wordpress
  --domain=<domain>
  --path=<path>
  --note=<text>

EXAMPLE
  platform inventory reserve \
    --name=bachvan \
    --application=wordpress \
    --domain=bachvan.com.vn \
    --http-port=8083 \
    --path=/opt/bachvan
EOF
