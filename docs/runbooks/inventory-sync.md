# Runbook — Inventory Sync

Site đã tồn tại:

```bash
platform-v2 inventory sync nvh
```

Site chưa tồn tại trong v2:

```bash
platform-v2 inventory sync nvh   --name=nvh   --path=/opt/nvh
```

Sau đó:

```bash
platform-v2 inventory validate
platform-v2 inventory show nvh
```
