# Git Safe Directory Runbook

Normalize:

```bash
sudo platform-v2 git normalize
```

Trust and verify:

```bash
sudo platform-v2 git trust /opt/nvh
sudo platform-v2 git verify /opt/nvh
sudo platform-v2 git info /opt/nvh
```

Inspect:

```bash
sudo git config --show-origin --get-all safe.directory
```

There should be no blank value.
