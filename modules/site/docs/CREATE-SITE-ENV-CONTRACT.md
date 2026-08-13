# Create Site Environment Contract

## Canonical environment template

Đối với `platform site create` và mọi flow tạo mới managed Docker site, Platform phải khởi tạo `.env` theo thứ tự ưu tiên sau:

1. `.env.docker.example` — **canonical / bắt buộc ưu tiên khi tồn tại**.
2. `.env.example` — chỉ là **compatibility fallback** khi repository không có `.env.docker.example`.
3. Nếu cả hai đều không tồn tại và `.env` chưa có, provisioning phải dừng với lỗi rõ ràng.

Không được đổi ngược thứ tự này trong các lần refactor sau.

## Lý do

`.env.docker.example` định nghĩa Docker runtime contract của application repository, bao gồm các giá trị network/service như:

- `DB_HOST=db`
- `DB_PORT=3306`
- `REDIS_HOST=redis`
- `REDIS_PORT=6379`
- `NODEJS_SERVER_URL=http://socket:6001`
- các biến bắt buộc bởi `compose.yaml` như `MARIADB_ROOT_PASSWORD`, `REDIS_PASSWORD`.

`.env.example` có thể phục vụ local/dev và không được coi là Docker template mặc định.

## Platform-owned values

Sau khi copy template, Platform chỉ nên inject/rotate các giá trị thuộc identity hoặc instance-specific state, ví dụ:

- `APP_NAME`
- `APP_ENV=production`
- `APP_DEBUG=false`
- `APP_URL`
- `APP_KEY`
- `DB_DATABASE`
- `DB_USERNAME` khi cần default
- `DB_PASSWORD`
- `MARIADB_ROOT_PASSWORD`
- `REDIS_PASSWORD`
- `BRIDGE_SECRET_KEY`
- `.docker-platform.env`: `COMPOSE_PROJECT_NAME`, `HTTP_PORT`, `SOCKET_PORT`

Không hard-code lại toàn bộ Docker runtime contract trong Platform nếu application repository đã định nghĩa nó trong `.env.docker.example`.

## Regression rule

Bất kỳ thay đổi nào vào Create/Duplicate/Restore provisioning phải bảo đảm:

```text
.env.docker.example > .env.example
```

và phải có regression test kiểm tra priority này.
