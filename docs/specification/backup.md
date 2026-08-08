# Backup / Restore Specification v1.0 dev.3

## Restore modes

### Existing site

```text
verify
→ preflight
→ emergency backup
→ restore source/database/storage
→ configure identity
→ deploy
→ nginx/ssl if identity changed
→ health
→ inventory sync
```

### Restore as new site

```text
verify
→ preflight new identity
→ extract snapshot
→ Site Provisioning Engine
→ import database/storage
→ nginx
→ ssl
→ health
→ Inventory commit
```

## DNS

DNS must resolve unless `--skip-dns-check` is supplied.

Cloudflare-proxied domains resolve to Cloudflare IPs. Resolve success is accepted; origin-IP equality is intentionally not required.
