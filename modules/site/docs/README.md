# Site Module v3.1

`site` owns provisioning orchestration.

Common lifecycle is implemented in:

```text
modules/site/lib/provision.sh
```

Data-source strategies remain separate:

```text
duplicate-live
restore-snapshot (future Package-008 integration)
create (future)
```
