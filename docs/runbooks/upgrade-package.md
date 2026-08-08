# Transactional Package Upgrade

```bash
sudo platform-v2 package upgrade /opt/Package-XXX-vNEW.zip
```

Expected success:

```text
Transactional upgrade Package-XXX: old -> new
[OK] ...
Đã nâng Package-XXX: old -> new
```

On failure, Package Manager restores the old files and old package record automatically.
