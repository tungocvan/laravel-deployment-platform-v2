# Site Create Runbook

Luôn chạy dry-run trước:

```bash
sudo platform-v2 site create   --name=demo   --domain=demo.example.com   --repo=git@github.com:user/repo.git   --dry-run
```

Sau khi kiểm tra port/path:

```bash
sudo platform-v2 site create   --name=demo   --domain=demo.example.com   --repo=git@github.com:user/repo.git
```
