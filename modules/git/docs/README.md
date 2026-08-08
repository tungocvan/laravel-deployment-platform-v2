# Git Module dev.2

## Why normalize?

This configuration:

```text
safe.directory=/opt/nvh
safe.directory=
```

does not mean `/opt/nvh` remains trusted. The empty value resets the previously accumulated safe-directory list.

Therefore every `platform_git_trust` begins by normalizing safe-directory entries.
