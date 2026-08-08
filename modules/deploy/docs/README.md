# Deploy Module dev.2

Docker Compose project identity is now part of deploy correctness.

Template compose files may contain:

```yaml
name: ${COMPOSE_PROJECT_NAME:-laravel-app}
```

The Platform MUST populate `COMPOSE_PROJECT_NAME` before running Compose.

For managed sites, Inventory `name` is authoritative.
