# Platform 2.1 Audit Log Contract

## Goal

Provide a cross-module, append-only operational audit trail without replacing module-owned history/state files.

## Event schema

Each audit event is one JSON object per line with these fields:

- `schema_version`
- `at` (UTC ISO-8601)
- `actor`
- `module`
- `command`
- `target`
- `result` (`success`, `failed`, `rollback-partial`, `rollback-failed`)
- `error_code` (nullable)
- `transaction_id` (nullable)
- `rollback_status` (`not-required`, `not-attempted`, `success`, `partial`, `failed`)

## Storage

Default root: `$PLATFORM_HOME/state/audit`.

Events are written to monthly JSONL files:

`events-YYYY-MM.jsonl`

Directory permissions should be restrictive and event files should be append-only by convention. The primitive must append complete JSON lines and never rewrite prior records.

## Sensitive-data rule

Audit records MUST NOT contain:

- passwords
- access tokens
- API keys
- private keys
- `.env` contents
- database credentials
- raw command lines that may embed secrets
- arbitrary environment dumps

The Phase 3A primitive therefore accepts only the fixed schema above. It intentionally does not accept a generic free-form metadata object.

`target` must be a logical identifier such as a site name, package id, domain, or repository path. Callers must not pass credentials or secret-bearing URLs.

## Relationship to existing evidence

Existing Package history, restore history, lifecycle state/archive metadata and other module-owned records remain authoritative for their own business details. Audit is a cross-module operational index, not a replacement.

## Failure semantics

Audit write failure must return non-zero to the caller. Modules may decide whether audit is mandatory for a specific destructive operation in later integration phases. Phase 3A does not change production workflow behavior.

## Phase 3A scope

- append-only core audit primitive
- deterministic actor/time/root overrides for tests
- schema validation
- restrictive file permissions
- deterministic tests
- bootstrap integration

No production module emits audit events until a later Phase 3 integration slice.
