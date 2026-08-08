# Backup / Restore Runbook

Dry-run existing restore:

```bash
sudo platform-v2 backup restore nvh-test latest --dry-run
```

Restore existing:

```bash
sudo platform-v2 backup restore nvh-test latest
```

Restore as new:

```bash
sudo platform-v2 backup restore nvh-test latest   --as=nvh-recovery   --domain=recovery.tungocvan.com   --database=db_nvh_recovery   --dry-run
```
