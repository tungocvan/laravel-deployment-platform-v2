# Platform 2.1 Transaction + Rollback Framework

## Status

Phase 2 foundation specification.

This document defines shared transaction mechanics only. Module-owned business ordering, safety policy, and recovery semantics remain owned by each module.

## Goals

- Remove duplicated transaction bookkeeping.
- Provide deterministic reverse-order rollback.
- Continue rollback after an individual rollback action fails.
- Preserve backward compatibility for workflows not yet migrated.
- Support workflows that intentionally do not auto-rollback destructive state.
- Provide a stable base for later audit-log and rollback error-code work.

## Non-goals

- No repository-wide migration in one change.
- No automatic inference of rollback actions.
- No nested transactions in the first implementation.
- No forced rollback for restore-existing workflows.
- No replacement of module-owned backup, verification, health, or conflict logic.
- No audit-log implementation in Phase 2A.

## Current transaction/rollback inventory

### Package upgrade

`modules/package/lib/package.sh` already implements a transaction directory, file backup, old package record backup, candidate install, candidate verify, manual rollback, history append, and cleanup.

Reusable mechanics:

- transaction lifecycle
- rollback registration
- reverse-order rollback execution
- cleanup
- rollback failure accounting

Module-owned semantics:

- which payload files are backed up
- package record normalization
- package upgrade history
- install/verify ordering

### Site disable

`modules/lifecycle/lib/lifecycle.sh` uses `trap ERR` plus local state flags (`nginx_disabled`, `docker_stopped`) and manually reverses Docker/Nginx operations.

Reusable mechanics:

- execute rollback only for completed steps
- reverse ordering
- best-effort continuation

Module-owned semantics:

- Nginx before Docker on forward path
- Docker before Nginx on rollback path
- lifecycle state persistence

### Site provisioning / restore-as-new

`modules/site/lib/provision.sh` exposes `site_provision_cleanup_new_target`, which aggregates Docker, Nginx, SSL, and filesystem cleanup.

`modules/backup/lib/backup.sh` calls that cleanup from an ERR trap for restore-as-new before commit.

Reusable mechanics:

- rollback action registration
- pre-commit cleanup
- commit boundary

Module-owned semantics:

- what constitutes a newly-created target
- whether SSL/Nginx were newly created
- source/database/storage restore ordering

### Restore-existing

Restore-existing creates an emergency backup, but intentionally does not automatically restore that snapshot after a later failure. This avoids rollback-on-rollback risk.

Therefore the shared framework MUST allow a workflow to:

- register no destructive rollback action;
- retain recovery evidence;
- report rollback as intentionally not attempted.

## Core contract

Phase 2A exposes shell primitives from `core/lib/transaction.sh`:

- `platform_tx_begin <name>`
- `platform_tx_register <callback> [args...]`
- `platform_tx_commit`
- `platform_tx_rollback`
- `platform_tx_cleanup`
- `platform_tx_active`
- `platform_tx_name`
- `platform_tx_rollback_failures`

### Begin

- Starts exactly one transaction in the current shell process.
- Nested transactions are rejected by returning non-zero.
- Begin does not create filesystem state by itself.

### Register rollback

- Registers a shell function/callback plus an argument vector.
- Callback names are validated as shell functions before registration.
- Arguments are stored as arrays; no `eval` is used.
- Registration requires an active transaction.

### Commit

- Marks the transaction successful.
- Discards registered rollback actions.
- Leaves no transaction active.
- Does not invoke cleanup callbacks.

### Rollback

- Executes only registered actions.
- Executes actions in exact reverse registration order (LIFO).
- Continues after a rollback callback fails.
- Returns zero only if every rollback action succeeds.
- Records the count of failed rollback actions for the caller.
- Does not convert module-specific recovery policy into generic behavior.

### Cleanup

- Resets all in-memory transaction state.
- Is idempotent.
- Does not run rollback actions.

## Error ownership

The transaction library returns shell status; it does not call `die()` or `platform_die()` for ordinary control flow.

The calling workflow owns user-visible error IDs and exit classes. Later migration may use:

- operation failed + rollback succeeded -> operation-specific error
- operation failed + rollback partially/fully failed -> exit class `ROLLBACK` (8)

Exact module-specific identifiers are deferred until a real workflow migration.

## Safety rules

1. Register rollback only after the forward step has completed successfully, unless the rollback callback is explicitly idempotent for a partially-created resource.
2. Rollback callbacks should be idempotent whenever practical.
3. Rollback callbacks must not call `exit`.
4. Rollback failure must not stop remaining rollback actions.
5. Commit must occur only after the workflow's final verification gate.
6. Existing restore/emergency-backup policy remains unchanged until separately reviewed.
7. No secret values may be embedded into transaction names or later audit records.

## Phase 2 delivery sequence

### Phase 2A — Core mechanics

- Add `core/lib/transaction.sh`.
- Load it from Core bootstrap.
- Add deterministic tests for begin/register/commit/cleanup.
- Add deterministic reverse-order rollback test.
- Add rollback-failure-continuation test.
- No production workflow migration yet.

### Phase 2B — Representative migration

Recommended first migration: package upgrade transaction bookkeeping, because it already has explicit backup/restore boundaries and verification before commit.

The migration must preserve package-owned payload backup, package record, and history semantics.

### Phase 2C — Lifecycle migration

After Package runtime verification, evaluate Site disable/provisioning as second consumers.

### Deferred

- restore-existing automatic rollback
- archive/purge destructive rollback
- audit log
- machine-readable transaction history
- nested transactions
- cross-process transaction recovery

## Acceptance criteria for Phase 2A

- Existing `make test` passes.
- Existing `make lint` passes.
- Transaction tests pass on the VPS.
- Rollback order is proven LIFO.
- One rollback failure does not skip later rollback callbacks.
- Commit prevents rollback actions from running.
- Cleanup is idempotent.
- No existing module runtime behavior changes in Phase 2A.
