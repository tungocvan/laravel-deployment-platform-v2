# Git Module dev.2

## Why normalize?

This configuration:

```text
safe.directory=/opt/nvh
safe.directory=
```

does not mean `/opt/nvh` remains trusted. The empty value resets the previously accumulated safe-directory list.

Therefore every `platform_git_trust` begins by normalizing safe-directory entries.

## Handoff — Git Update SSH alias fallback (2026-11-16)

- Branch: `fix/git-shared-ssh-alias-transport-20261116`.
- Root cause: `git update` fetched canonical `origin` using default SSH
  identity; Repository Access UI separately discovered an authorized
  `github-owner-repo` alias.
- Shared resolver in `modules/git/lib/git.sh`; used by Git Update and
  Repository Access UI. Canonical `origin` and Inventory are preserved.
- Focused checkpoint: `bash modules/git/tests/test-git.sh`.
- Next gate after focused PASS: `bash modules/ui/tests/test-ui.sh`,
  then operator UI acceptance on staging. Do not claim PASS without results.
- No Production fetch, deploy, restart, migrate or remote rewrite was executed
  as part of this GitHub change.
