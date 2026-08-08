# Site Lifecycle

States managed by Package-011:

```text
active
maintenance
disabled
```

The lifecycle record is stored separately from Inventory:

```text
state/site-lifecycle/<site>.json
```

This avoids changing Inventory schema during the first lifecycle release.
