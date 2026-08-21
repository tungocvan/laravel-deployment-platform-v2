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

  migrate-remote <site> [--to=<git-url>] [--require-compatible-main] [--dry-run] [--yes]
      Chuyển origin của managed site sang repository mới một cách an toàn.
      Default target: PLATFORM_DEFAULT_SITE_REPO hoặc canonical Laravel repository.
      Verify target branch/history trước khi đổi remote; không pull/reset/deploy.
      --require-compatible-main: site phải ở main và old/main phải là ancestor
      của new/main. Kho mới có thể bằng hoặc đi trước kho cũ, nhưng không được
      diverged hoặc thiếu history của kho cũ.
      --require-identical-main được giữ làm alias tương thích cho menu/automation cũ.
      Sau thành công sẽ sync Inventory và ghi audit log.

  bootstrap-remote <site> --to=<empty-git-url> [--dry-run] [--yes]
      Khởi tạo một repository mới hoàn toàn trống từ main của repository hiện tại.
      Source chuẩn được đọc trực tiếp từ old repository/main, không lấy source local.
      Khi --yes: kiểm tra quyền push/delete bằng ref tạm, push old/main -> new/main,
      verify commit SHA + tree, rồi mới đổi origin của site và sync Inventory.
      HEAD, working tree, deploy, database và container của site được giữ nguyên.
      Nếu bất kỳ verify nào thất bại, origin site không đổi hoặc được rollback.

  sync-repositories --from=<source-git-url> --to=<target-git-url> [--dry-run] [--yes]
      Đồng bộ một chiều branch main trực tiếp từ repository nguồn sang repository đích.
      Cho phép target trống, bằng source, hoặc đang behind source theo cùng history.
      Từ chối target ahead hoặc diverged; tuyệt đối không force-push và không tự merge.
      Không đọc source project local, không đổi site origin/Inventory, không deploy,
      không thao tác database hoặc container. Sau push verify lại SHA + source tree.
EOF
