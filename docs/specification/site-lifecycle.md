# Site Lifecycle Specification v1.1

Lifecycle is reversible:

```text
active ↔ maintenance
active ↔ disabled
active → archived → active
```

Archive is a safe detach:

```text
backup + verify
→ nginx disable
→ docker compose down (keep volumes)
→ preserve source
→ preserve SSL
→ remove active Inventory record
→ archived record
```

Permanent resource destruction belongs to Package-012.
