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

  update <site> [--dry-run] [--yes]
      Cập nhật code site từ origin bằng fast-forward only.
      Từ chối working tree bẩn, detached HEAD, local-ahead hoặc diverged branch.
      Bỏ qua các runtime artifact do Platform quản lý (.env, .docker-platform.env,
      compose.queue.yaml, compose.socket.yaml, compose.scheduler.yaml).
      Update code không tự chạy Deploy; sau đó dùng `platform deploy run <site>` khi cần.
EOF
