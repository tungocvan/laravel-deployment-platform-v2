# Frontend Build

For Docker multi-stage Laravel/Vite sites:

```bash
platform-v2 deploy frontend detect nvh
sudo platform-v2 deploy frontend build nvh
```

Expected strategy:

```text
frontend_strategy: docker-multistage
docker_services: app, web
```

No npm installation on the VPS host is required.
