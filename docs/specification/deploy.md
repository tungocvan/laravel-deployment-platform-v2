# Deploy Specification v1.1 dev.2

## Frontend strategy

Detection priority:

```text
Dockerfile contains `AS frontend-build`
    -> docker-multistage
otherwise
    -> host package-manager fallback
```

For Docker multi-stage projects:

```text
docker compose build app web
→ docker compose up -d app web
→ deploy health
```

Queue, scheduler, socket, db and redis are not rebuilt by frontend-only action.

The Node/npm runtime inside Docker is the source of truth for frontend builds.
