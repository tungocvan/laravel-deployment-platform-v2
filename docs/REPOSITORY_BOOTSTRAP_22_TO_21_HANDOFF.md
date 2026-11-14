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
- Chưa chạy tests thực tế, chưa xác nhận UI PASS, chưa tạo PR, chưa merge hoặc deploy.
- Rủi ro cần kiểm tra: `gh auth` dưới tài khoản chạy Platform, quyền tạo repository private, branch protection, SSH identity, status của GitHub API khi repo chưa tồn tại.
