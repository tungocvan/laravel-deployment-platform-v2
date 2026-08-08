# Migration

Dry run:

```bash
DRY_RUN=1 sudo ./migration/migrate-v1-layout.sh   /opt/laravel-deployment-platform   /opt/laravel-deployment-platform-v2
```

Apply:

```bash
DRY_RUN=0 sudo ./migration/migrate-v1-layout.sh   /opt/laravel-deployment-platform   /opt/laravel-deployment-platform-v2
```
