# Platform 2.1 Error Migration Map

Status: Draft
Target: Platform 2.1 Phase 1C

## 1. Purpose

Phase 1C migrates module-level failures from generic legacy `die()` / raw non-zero exits to stable error identifiers and coarse process exit classes without changing business behavior.

This document is a migration map, not permission for a repository-wide mechanical replacement. Each module slice must be reviewed and tested independently.

## 2. Exit classes

| Exit | Class | Typical use |
|---:|---|---|
| 2 | USAGE | missing/invalid CLI arguments, invalid options |
| 3 | VALIDATION | invalid requested values or failed preconditions |
| 4 | DEPENDENCY | required executable/service/runtime dependency unavailable |
| 5 | CONFLICT | resource ownership/collision/unsafe state |
| 6 | OPERATION | execution or state mutation failed |
| 7 | HEALTH | post-operation health/verification gate failed |
| 8 | ROLLBACK | rollback failed or state became uncertain |
| 9 | INTERNAL | unexpected core/platform invariant failure |

Legacy exit 1 remains valid for failure sites not yet migrated.

## 3. Namespace rules

Stable identifiers use uppercase module namespaces:

```text
CORE.*
SITE.*
DEPLOY.*
DATABASE.*
INVENTORY.*
GIT.*
BACKUP.*
NGINX.*
SSL.*
DOCTOR.*
PACKAGE.*
PLUGIN.*
LIFECYCLE.*
PURGE.*
UI.*
```

Identifiers describe the condition, not the message wording. Human messages may improve without changing automation contracts.

## 4. Migration order

### Tier 0 — completed core contract

- `CORE.MODULE_NOT_FOUND` -> USAGE (2)
- `CORE.COMMAND_NOT_FOUND` -> USAGE (2)
- `CORE.ROOT_REQUIRED` -> DEPENDENCY (4)
- `CORE.REQUIRED_COMMAND_MISSING` -> DEPENDENCY (4)

### Tier 1 — deterministic input/state validation

Migrate first because these failures are easy to prove with isolated tests and do not require external infrastructure.

Priority modules:

1. Inventory
2. Git
3. Package manifest/input validation
4. Site read-only argument validation
5. Backup read-only selectors

Typical identifiers:

```text
INVENTORY.ARGUMENT_REQUIRED
INVENTORY.INVALID_OPTION
INVENTORY.INVALID_PORT
INVENTORY.RESOURCE_NOT_FOUND
INVENTORY.PORT_CONFLICT
GIT.REPOSITORY_NOT_FOUND
GIT.INVALID_REMOTE
PACKAGE.INVALID_MANIFEST
SITE.ARGUMENT_REQUIRED
BACKUP.BACKUP_NOT_FOUND
```

### Tier 2 — dependency and conflict failures

Migrate after Tier 1 contracts are stable.

Examples:

```text
DEPLOY.DOCKER_PLATFORM_MISSING
NGINX.CONFIG_MISSING
NGINX.DOMAIN_CONFLICT
SSL.NGINX_REQUIRED
SSL.CERTIFICATE_IN_USE
DATABASE.SERVICE_UNAVAILABLE
```

These may require VPS evidence but should not yet alter transaction/rollback behavior.

### Tier 3 — operational failures

Operational execution failures should be migrated only after the error taxonomy is stable and tests can distinguish execution failure from validation/conflict.

Examples:

```text
DEPLOY.BUILD_FAILED
DEPLOY.MIGRATION_FAILED
DATABASE.IMPORT_FAILED
BACKUP.CREATE_FAILED
NGINX.RELOAD_FAILED
SSL.ISSUE_FAILED
PACKAGE.INSTALL_FAILED
```

### Tier 4 — health and rollback failures

Defer broad migration until shared transaction/rollback primitives exist.

Examples:

```text
DEPLOY.HEALTH_FAILED
BACKUP.RESTORE_VERIFY_FAILED
SITE.PROVISION_ROLLBACK_FAILED
PACKAGE.ROLLBACK_FAILED
PURGE.ROLLBACK_UNAVAILABLE
```

## 5. Module ownership map

| Namespace | Owner responsibility | First migration focus | Defer until later |
|---|---|---|---|
| INVENTORY | managed resource index/reservations | usage, port validation, not-found/conflict | runtime discovery/state mutation failures |
| GIT | repo validation/normalization | repo/path/remote validation | mutation/normalize failures |
| PACKAGE | package validation/history | manifest/version/input validation | transactional install/rollback |
| SITE | lifecycle orchestration | read-only selectors/argument validation | provision/duplicate/rename rollback paths |
| BACKUP | snapshot/verify/restore | backup selector/not-found/input validation | create/restore operational + rollback |
| DATABASE | DB operations | input/dependency validation | import/restore execution |
| DEPLOY | deploy lifecycle | preflight/dependency validation | build/migrate/health/rollback |
| NGINX | host proxy lifecycle | config/domain validation/conflict | render/reload operational failures |
| SSL | certificate lifecycle | domain/config/conflict validation | certbot issue/remove execution |
| DOCTOR | read-only diagnostics | argument/target validation | diagnostic aggregation semantics |
| PLUGIN | plugin lifecycle | name/path/input validation | install/remove operation failures |
| LIFECYCLE | reversible internal lifecycle | metadata/precondition validation | archive/restore operational rollback |
| PURGE | irreversible destruction | safety/precondition validation | destructive execution/history failures |
| UI | interactive client | input/navigation validation only | must not own backend business errors |

## 6. Rules for each migration slice

Before changing a failure site:

1. identify the module owner;
2. classify the failure by exit class;
3. assign one stable identifier;
4. preserve existing human meaning unless improvement is clearly safe;
5. add isolated tests for both failure and success paths;
6. do not convert nested/raw subprocess failures blindly;
7. do not mask a more specific child-module error with a generic parent error;
8. keep legacy exit 1 for sites not yet classified;
9. require VPS evidence when Docker/Nginx/Certbot/database/runtime state is involved.

## 7. First representative slice — Inventory input validation

Phase 1C implementation starts only with deterministic Inventory CLI validation:

```text
inventory show <key> missing
    -> INVENTORY.ARGUMENT_REQUIRED / USAGE (2)

inventory unreserve <name> missing
    -> INVENTORY.ARGUMENT_REQUIRED / USAGE (2)

inventory reserve unknown option
    -> INVENTORY.INVALID_OPTION / USAGE (2)

inventory reserve missing --name
    -> INVENTORY.ARGUMENT_REQUIRED / USAGE (2)

inventory reserve non-numeric/out-of-range --http-port
    -> INVENTORY.INVALID_PORT / VALIDATION (3)
```

Conflict errors raised during reservation and operational Python/state failures are intentionally excluded from this first slice.

## 8. Completion gate for Phase 1C first slice

- shell syntax passes;
- Inventory tests cover all migrated IDs and exit codes;
- existing Inventory success paths remain unchanged;
- full `make test` passes;
- lint passes;
- no Docker/Nginx/Certbot mutation is required for verification;
- migration map is updated if implementation reveals a semantic mismatch.
