# Production Site Operations V2

## Runtime contract

All production operations resolve `SITE -> Inventory path -> Compose project -> discovered services -> Laravel app service`. Compose topology is discovered with `config --services`; container names and fixed service counts are not treated as contracts.

Repository helper scripts (`production-debug.sh`, `run-docker-artisan.sh`, `run-updated-env.sh`, `production-cleanup.sh`) are capabilities, not requirements. Native Platform operations remain available for legacy managed sites.

## Update Site

`platform site update <site> --dry-run` fetches upstream, requires a clean working tree, compares commits, reports changed files, detects build-sensitive changes and migration risk. Updates are fast-forward only. New migrations are blocked unless the operator explicitly uses `--migrate`; migration updates create a verified backup first. Production overlays are never cleaned automatically.

Database readiness for Production Site Update is Laravel-native: the application is bootstrapped inside the discovered app service and the configured database connection is tested through Laravel. The production-scoped readiness override intentionally avoids assuming that `DB_*` variables are exported directly into the container process environment.

### Partial-update recovery / Runtime Reconcile

If source has already advanced but a post-update runtime step failed, use the explicit reconcile path instead of repeating or forcing the Git update:

```bash
platform-v2 site update <site> --reconcile --dry-run
platform-v2 site update <site> --reconcile --yes
```

Reconcile is source-neutral and migration-neutral. It performs runtime identity/preflight, Compose reconcile with `--no-build`, Laravel database readiness, Laravel optimize, queue restart, runtime health and Inventory sync. It does **not** fetch/merge Git, build images, run database migrations or create a migration backup.

The interactive Sites menu also exposes `Reconcile / Resume Runtime`. The UI always previews first and requires a separate execution confirmation.

## Environment

`platform site env <site> <env-file> --dry-run` reports only changed/added/removed key names. Values are never printed. Apply mode checkpoints the existing `.env`, preserves runtime permissions, reconciles Compose without build when environment-sensitive keys changed, refreshes Laravel config and restores the checkpoint if health validation fails.

## Diagnostics, Artisan, Runtime

Diagnostics is read-only and combines live Compose topology, Git status, Laravel environment evidence and recent Compose logs. Artisan commands run in the discovered app service; destructive database reset commands are blocked from this production path. Runtime Status shows discovered services and Compose `ps -a` rather than assuming a fixed number of containers.

## Cleanup

Cleanup is report-only by default. Apply mode is site-local: large Laravel log files may be rotated and Laravel caches cleared. Docker image/build-cache cleanup is explicitly identified as host-wide and is not automatic. Docker volumes are never pruned by this operation.

## Recovery semantics

A checkpoint is a local reversible copy used by a single operation. A backup is the verified Platform backup set. Automatic rollback is claimed only where the operation actually restores its checkpoint. Update migration risk uses a verified backup but does not claim that every external side effect can be automatically reversed.

Production Runtime Reconcile exists specifically for a partial-update state where Git/source is already current but runtime/post-update work must be safely resumed. It must not be treated as a migration recovery mechanism.

## Acceptance evidence — 2026-09-17

Targeted `production-operations-contract.sh` and interactive UI were reported PASS after the final Reconcile / Resume Runtime flow was added.

Production site `tnv` also completed a real `--reconcile --yes` run end-to-end: Compose reconciled all discovered services, Laravel-native database readiness succeeded, optimize and queue restart completed, runtime health showed the managed services healthy, and Inventory sync completed while the application commit remained unchanged at `5b1a1040de6a25dc7fe35231748997233541ee02`.

The three legacy empty overlays (`compose.queue.yaml`, `compose.scheduler.yaml`, `compose.socket.yaml`) were correctly reported as stale, non-active placeholders: they did not block the operation and were not automatically deleted.
