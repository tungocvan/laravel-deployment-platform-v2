# Contributing

## Module contract

Mỗi module phải có:

```text
modules/<name>/
├── commands/
├── lib/
├── docs/
└── tests/
```

Command phải:

- dùng `set -Eeuo pipefail`
- source core bootstrap
- validate arguments
- không log secrets
- trả exit code chuẩn
- có help
- có test

## Commit format

```text
feat(site): add register command
fix(inventory): prevent duplicate port
docs(deploy): document health gate
test(database): add backup coverage
```
