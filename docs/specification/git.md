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
