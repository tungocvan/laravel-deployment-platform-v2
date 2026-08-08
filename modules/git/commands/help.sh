#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform git <command> [options]

COMMANDS
  normalize
      Dọn empty/duplicate safe.directory entries.

  trust <path>
      Trust Git repository path.

  verify <path>
      Trust + verify Git working tree và HEAD.

  info <path>
      Path, branch, commit, remote.

  remote <path>
  branch <path>
  commit <path>
EOF
