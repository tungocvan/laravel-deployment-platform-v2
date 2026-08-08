# Inventory Module dev.2

`sites` chỉ chứa Laravel applications.

`reserved_resources` chỉ dùng để giữ tài nguyên bên ngoài như WordPress, service cũ hoặc port đã dành riêng.

Port allocator phải kiểm tra:

1. Laravel sites.
2. Reserved resources.
3. Host listeners (`ss`).
4. Docker published ports.
