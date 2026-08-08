# Site Provisioning Specification v3.1

## Principle

Create, Duplicate and Restore MUST NOT reimplement Deploy/Nginx/SSL lifecycle.

Shared target pipeline:

```text
configure target
→ deploy prepare
→ strategy data phase
→ deploy finalize
→ nginx
→ ssl
→ health
→ inventory commit
```

Inventory commit is always the last step for a newly provisioned site.
