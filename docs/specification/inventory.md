# Inventory Specification — dev.2

## Laravel sites

`sites` chỉ dành cho Laravel applications do Platform quản lý.

## Reserved resources

`reserved_resources` dành cho external resources không do Laravel Deployment Platform quản lý nhưng cần giữ tài nguyên như port.

Ví dụ:

```json
{
  "name": "bachvan",
  "type": "external",
  "application": "wordpress",
  "domain": "bachvan.com.vn",
  "http_port": 8083,
  "path": "/opt/bachvan",
  "managed": false
}
```

## Port policy

Port được xem là đã dùng nếu xuất hiện trong:

- Laravel sites
- reserved resources
- `ss -lnt`
- Docker published ports
