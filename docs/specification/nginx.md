# Nginx Module Specification v1

## Ownership

Platform-managed configs contain:

```text
# Managed by Laravel Deployment Platform
```

This marker is required before automatic overwrite/remove.

## Ensure contract

```text
validate domain/port
→ detect foreign server_name conflict
→ backup managed existing config
→ atomic render
→ enable symlink
→ nginx -t
→ reload
```

## Site Module integration

```bash
platform_nginx_ensure_proxy "$domain" "$http_port"
```

Site Module must not write `/etc/nginx` directly.
