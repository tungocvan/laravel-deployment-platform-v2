# Roadmap

## Platform 2.0 — Feature-complete baseline

Platform 2.0 established the modular CLI and the core operational lifecycle for Laravel sites running on Docker with host Nginx/Certbot integration.

Completed baseline capabilities include:

- modular dispatcher and module discovery;
- Inventory and reserved external resources;
- Site lifecycle and provisioning flows;
- Git normalization/verification;
- Deploy engine with health gate and frontend build strategies;
- Database operational commands;
- Backup/verify/restore;
- Nginx and SSL lifecycle;
- Doctor/preflight;
- Package Manager with transactional package upgrades;
- reversible lifecycle/archive flows;
- irreversible purge safety;
- interactive task-oriented UI.

Canonical project handoff: `docs/AI-HANDOFF.md`.

## Platform 2.1 — Stabilization / Production Hardening

Platform 2.1 does **not** prioritize new business commands. The goal is to make the existing Platform 2.0 capabilities more predictable, testable, auditable, and maintainable in production.

Implementation order:

1. **CLI + Error Contract**
   - standardized exit classes;
   - stable error identifiers;
   - backward-compatible human output;
   - dispatcher/core contract tests.

2. **Transaction + Rollback Framework**
   - shared transaction mechanics;
   - rollback registration and reverse-order execution;
   - explicit commit/cleanup behavior;
   - module-owned business rollback decisions.

3. **Audit Log**
   - append-only runtime audit events for mutating operations;
   - module/command/target/result/error/transaction context;
   - no secrets or committed runtime state.

4. **Integration Testing**
   - cross-module contract tests;
   - representative non-destructive end-to-end flows;
   - regression coverage for existing command paths;
   - VPS functional verification for Docker/Nginx/Certbot/database behavior.

5. **Doctor / Preflight Hardening**
   - improve diagnostics and actionable failure reporting;
   - keep Doctor read-only;
   - reuse standardized error/audit contracts where appropriate.

6. **Documentation + Release Discipline**
   - synchronize README, specifications, runbooks, CHANGELOG and VERSION policy;
   - formal release checklist and verification gates.

Detailed foundation contract: `docs/specification/PLATFORM-2.1-FOUNDATION.md`.

### Platform 2.1 guardrails

- preserve backward compatibility unless explicitly deprecated;
- do not move module business logic into Core;
- do not duplicate CLI/module behavior inside UI;
- Inventory commit for new sites stays after successful health verification;
- Deploy remains health-gated;
- destructive operations retain safety gates;
- runtime state, secrets, backups and certificates remain outside Git.

## Later work

New capabilities should be considered only after the Platform 2.1 stabilization gates are satisfied and measured production needs justify them.
