# Platform 2.1 Foundation Specification

Status: Draft
Target: Laravel Deployment Platform 2.1
Scope: stabilization and production hardening only

## 1. Goal

Platform 2.1 does not add new business capabilities. It standardizes the existing Platform 2.0 behavior so modules can share predictable CLI contracts, error semantics, transaction/rollback behavior, audit events, tests, documentation, and release discipline.

The existing module architecture remains the source architecture. Core must not absorb module business logic.

## 2. Compatibility rules

1. Existing command paths must continue to work unless an explicit deprecation is documented.
2. Human-readable output may be normalized incrementally, but scripts must not lose existing success/failure semantics without a migration note.
3. Runtime state, secrets, backups, certificates, project `.env` files, and generated artifacts remain outside Git.
4. UI remains a client of CLI/module APIs and must not duplicate Docker, Nginx, Certbot, Git, backup, deploy, or lifecycle business logic.
5. Inventory commit for a newly provisioned site remains the final step after health succeeds.
6. Deploy remains health-gated.
7. Destructive operations retain backup/verify/dry-run/confirmation protections where currently available.

## 3. Delivery order

Platform 2.1 is implemented in the following order because later layers depend on earlier contracts.

### Phase 1 — CLI and error contract

Define a stable core contract for:

- standard exit status classes;
- machine-stable error identifiers;
- human-readable error messages;
- consistent `info`, `success`, `warn`, and `error` behavior;
- dispatcher errors for unknown module/command;
- optional structured output without breaking default human output.

Initial implementation must be backward-compatible: existing successful commands continue to return `0`, and failures continue to be non-zero even before every module is migrated to specific error classes.

### Phase 2 — Transaction and rollback primitives

Add shared primitives only for cross-cutting transaction mechanics, not module business decisions.

The framework must support:

- transaction begin;
- registration of rollback actions;
- ordered rollback execution in reverse registration order;
- commit;
- cleanup;
- clear failure propagation;
- no silent swallowing of rollback failures.

Modules remain responsible for deciding what constitutes a rollback action.

### Phase 3 — Audit log contract

Define an append-only runtime audit event model for mutating operations.

Minimum fields:

- timestamp;
- actor/process context when available;
- module;
- command;
- target/resource identity;
- action/result;
- stable error identifier when failed;
- transaction identifier when applicable.

Audit data is runtime state and must not be committed to Git.

### Phase 4 — Integration tests

Expand tests from smoke checks into contract tests covering:

- dispatcher success/failure;
- module discovery;
- standard error identifiers/exit classes;
- transaction commit/rollback ordering;
- audit event creation;
- representative non-destructive module flows using fixtures/mocks;
- regression tests for backward-compatible command paths.

Runtime Docker/Nginx/Certbot/database behavior still requires VPS functional verification where mocks cannot prove the real contract.

### Phase 5 — Documentation and release discipline

Synchronize README, ROADMAP, specifications, runbooks, CHANGELOG, VERSION policy, and release checklist only after implemented behavior is verified.

## 4. CLI error model

Platform 2.1 separates three concepts:

1. human message — readable explanation for the operator;
2. stable error identifier — suitable for logs/tests/automation;
3. process exit status — coarse failure class for shell integration.

Proposed initial exit classes:

| Exit | Class | Meaning |
|---:|---|---|
| 0 | OK | command completed successfully |
| 2 | USAGE | invalid arguments, unknown command/module, invalid option |
| 3 | VALIDATION | requested operation failed precondition/validation |
| 4 | DEPENDENCY | required command/service/dependency unavailable |
| 5 | CONFLICT | resource conflict or unsafe state prevents operation |
| 6 | OPERATION | operational execution failed |
| 7 | HEALTH | post-operation verification/health gate failed |
| 8 | ROLLBACK | rollback itself failed or left an uncertain state |
| 9 | INTERNAL | unexpected platform/core failure |

During migration, generic legacy `exit 1` remains accepted where a module has not yet adopted a specific class. The migration must not convert known failures to success.

Stable error identifiers use uppercase namespace form:

```text
CORE.MODULE_NOT_FOUND
CORE.COMMAND_NOT_FOUND
CORE.REQUIRED_COMMAND_MISSING
CORE.ROOT_REQUIRED
<Module>.<Specific_Error>
```

Exact module namespaces should be normalized to uppercase before broad adoption.

## 5. Output contract

Default CLI output remains human-first. Existing colored prefixes are retained initially:

```text
[INFO]
[OK]
[WARN]
[ERROR]
```

A future machine-readable mode may emit JSON, but Phase 1 must not force JSON output onto existing commands.

Errors should be capable of carrying a stable identifier without requiring every existing caller to parse natural-language text.

## 6. Transaction boundaries

The shared transaction framework must never decide module-specific business ordering. For example:

- Site decides when Inventory may commit.
- Backup decides what snapshot verification means.
- Deploy decides health gates.
- Nginx decides config validation/reload behavior.
- SSL decides certificate lifecycle rules.

Core may provide lifecycle mechanics such as registering and executing rollback callbacks.

## 7. Audit boundaries

Audit logging is for operational accountability, not a replacement for domain state/history already owned by modules.

Examples:

- deploy history remains Deploy-owned;
- package history remains Package-owned;
- archive/purge metadata remains lifecycle/purge-owned;
- the audit log records that an operation was attempted and its result.

## 8. Verification gate for each Platform 2.1 change

Before a change is considered complete:

1. `bash -n` passes for changed shell files;
2. relevant unit/module tests pass;
3. core contract tests pass;
4. lint passes where applicable;
5. destructive commands are exercised with `--dry-run` when available;
6. production-dependent flows are verified on a VPS with runtime evidence;
7. documentation reflects only behavior that is actually implemented.

## 9. First implementation slice

The first code slice after this specification should be intentionally small:

1. add constants/helpers for exit classes and stable error identifiers in core;
2. preserve current `info/success/warn/error/die` call sites;
3. extend `die` or add a compatible companion helper so callers can opt into a specific identifier/exit class;
4. migrate only dispatcher-level failures first (`module not found`, `command not found`, missing root/command dependencies where safe);
5. add core tests proving old success paths still work and new failure contracts are stable;
6. do not mass-edit all modules in the same change.

This sequencing limits regression risk and provides a contract that later transaction, rollback, and audit work can depend on.
