# Project Charter

## Vision
CLI module hóa để quản lý deployment Laravel trên Docker.

## Principles
1. Core không chứa business logic.
2. Nghiệp vụ nằm trong module.
3. Specification trước implementation.
4. Inventory là cache/index có thể tái tạo.
5. Runtime state không commit.
6. Destructive operation cần backup + confirmation.
7. Deploy phải qua health gate.
8. Thay đổi lớn phân phối qua Package.
9. Package phải verify + rollback.
10. Staging trước production.
