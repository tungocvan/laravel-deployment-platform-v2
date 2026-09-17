# Production Site Operations V2

## Runtime contract

All production operations resolve `SITE -> Inventory path -> Compose project -> discovered services -> Laravel app service`. Compose topology is discovered with `config --services`; container names and fixed service counts are not treated as contracts.

Repository helper scripts (`production-debug.sh`, `run-docker-artisan.sh`, `run-updated-env.sh`, `production-cleanup.sh`) are capabilities, not requirements. Native Platform operations remain available for legacy managed sites.

## Update Site

`platform site update <site> --dry-run` fetches upstream, requires a clean working tree, compares commits, reports changed files, detects build-sensitive changes and migration risk. Updates are fast-forward only. New migrations are blocked unless the operator explicitly uses `--migrate`; migration updates create a verified backup first. Production overlays are never cleaned automatically.

## Environment

`platform site env <site> <env-file> --dry-run` reports only changed/added/removed key names. Values are never printed. Apply mode checkpoints the existing `.env`, preserves runtime permissions, reconciles Compose without build when environment-sensitive keys changed, refreshes Laravel config and restores the checkpoint if health validation fails.

## Diagnostics, Artisan, Runtime

Diagnostics is read-only and combines live Compose topology, Git status, Laravel environment evidence and recent Compose logs. Artisan commands run in the discovered app service; destructive database reset commands are blocked from this production path. Runtime Status shows discovered services and Compose `ps -a` rather than assuming a fixed number of containers.

## Cleanup

Cleanup is report-only by default. Apply mode is site-local: large Laravel log files may be rotated and Laravel caches cleared. Docker image/build-cache cleanup is explicitly identified as host-wide and is not automatic. Docker volumes are never pruned by this operation.

## Recovery semantics

A checkpoint is a local reversible copy used by a single operation. A backup is the verified Platform backup set. Automatic rollback is claimed only where the operation actually restores its checkpoint. Update migration risk uses a verified backup but does not claim that every external side effect can be automatically reversed.
