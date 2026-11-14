# Repository Bootstrap → Update (2026-11-14)

## Mục tiêu

- Menu 22 tạo repository GitHub **mới, chưa tồn tại**, private mặc định; push `source/main` giữ nguyên lịch sử.
- Menu 22 không đổi origin, Inventory, HEAD, worktree, Docker, database hoặc deploy.
- Menu 21 kiểm tra main lineage và đổi origin + Inventory sau khi người vận hành xác nhận.
- Repository đã tồn tại: menu 22 từ chối, không force push. Luồng replace cũ của CLI được giữ tương thích nhưng menu không gọi.

## Lệnh checkpoint (chỉ trên máy test/staging, KHÔNG trên Production)

```bash
git fetch origin
git switch feat/repository-bootstrap-then-migrate-20261114
git pull --ff-only
bash modules/git/tests/test-git.sh
```

Nếu focused test PASS, chạy regression theo bộ kiểm thử Platform tương ứng. UI acceptance menu 22/21 do operator xác nhận.

## Điều kiện vận hành

- GitHub CLI `gh` được xác thực và có quyền tạo repository dưới owner.
- SSH identity `/root/.ssh/github_tungocvan_ed25519` có quyền push repository mới.
- Dry-run chỉ xác minh quyền API/điều kiện source; không chứng minh quyền tạo repo hay push.
- Nếu tạo repo thành công nhưng push lỗi, repository được giữ để kiểm tra; không xóa tự động.
- Menu 21 vẫn yêu cầu URL canonical `git@github.com:owner/repo.git`.

## Handoff

- Branch: `feat/repository-bootstrap-then-migrate-20261114`
- Đã chạy `bash modules/git/tests/test-git.sh` và `bash modules/ui/tests/test-ui.sh` trên host Platform: cả hai exit 0. Operator xác nhận UI menu 22 PASS. Menu 22 đã tạo PRIVATE `tungocvan/laravel-inafo`, SHA `75da1f1d263d60ad29fc5a10a8ab0457f63b80a7`. Menu 21 dry-run và thực thi exit 0; site origin và Inventory đã chuyển sang repository mới, site HEAD giữ nguyên `4ce6c532536fe157a1f148780aab1bd80df1ea54` (behind 11). Không deploy, migrate database hay restart Docker. PR/merge Platform chưa thực hiện tại thời điểm cập nhật handoff.
- Rủi ro cần kiểm tra: `gh auth` dưới tài khoản chạy Platform, quyền tạo repository private, branch protection, SSH identity, status của GitHub API khi repo chưa tồn tại.
