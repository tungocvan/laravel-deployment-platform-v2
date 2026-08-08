# SSL Module Specification v1

## Purpose

Centralize Certbot/Let's Encrypt lifecycle.

## Contract

Issue:

```text
validate domain
→ require Nginx config
→ certbot --nginx
→ verify certificate files
```

Remove:

```text
validate domain
→ ensure cert exists
→ refuse if enabled Nginx still references cert
→ certbot delete
```

Site Module must not invoke Certbot directly after integration.
