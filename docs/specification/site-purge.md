# Site Purge Specification v1

Purge owns irreversible resource destruction.

```text
backup safety
→ nginx disable
→ docker down -v
→ nginx config removal
→ ssl removal
→ source removal
→ inventory/archive removal
→ purge history
```

Source deletion is automatically permitted only beneath `/opt/projects/*`.
