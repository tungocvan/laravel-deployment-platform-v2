# Package Specification v2 — Transactional Upgrade

Upgrade contract:

```text
1. Validate ZIP/checksum/manifest.
2. Load current package record.
3. Backup every payload target file.
4. Run candidate installer in transaction mode.
5. Run candidate verify.
6. Commit record/history only after verify succeeds.
7. On failure: restore files + restore old record.
```

Package version must never advance on a failed verify.
