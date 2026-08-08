# Purge Runbook

Recommended:

```bash
sudo platform-v2 site archive ntd-test
sudo platform-v2 site purge ntd-test --dry-run
sudo platform-v2 site purge ntd-test
```

Keep source/volumes:

```bash
sudo platform-v2 site purge ntd-test   --keep-source   --keep-volumes   --dry-run
```
