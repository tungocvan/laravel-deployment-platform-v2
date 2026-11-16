# Git Module Specification v1 — dev.2

## Safe-directory reset semantics

An empty `safe.directory` value resets prior values in Git's multi-valued configuration.

The Platform therefore MUST:

1. Read all safe.directory values.
2. Remove empty values.
3. De-duplicate non-empty values.
4. Write normalized values back.
5. Add the requested canonical path if absent.
6. Verify the repository with Git itself.

All Git-consuming modules should call `platform_git_verify`.

## SSH identity selection for Git Update

- GitHub canonical `git@github.com:owner/repo.git` remains in origin and Inventory.
- Git Update checks read access with the existing transport, then tries only
  preconfigured `github-owner` and `github-owner-repo` SSH aliases.
- Candidate aliases must resolve to `github.com` and pass `git ls-remote`.
- A successful alias is applied only to the individual Git fetch via
  `git -c url.<alias-url>.insteadOf=<canonical-url>`; no persistent rewrite,
  private-key modification, or remote mutation is permitted.
- Missing credentials fail closed. No automatic key creation in Git Update.
- Dry-run may fetch Git refs but must not merge, deploy or change site files.
- Repository Access UI uses the same shared alias discovery function.
- The resolver is intentionally read-only and does not infer write permission.
