# Nginx Site Runbook

Check domain availability:

```bash
sudo platform-v2 nginx conflicts nvh.tungocvan.com
```

Create reverse proxy:

```bash
sudo platform-v2 nginx ensure nvh.tungocvan.com 8084
```

Inspect:

```bash
platform-v2 nginx show nvh.tungocvan.com
sudo platform-v2 nginx verify
```
