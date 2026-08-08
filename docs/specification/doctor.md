# Doctor / Preflight Specification v1.0 dev.2

`doctor domain` is read-only.

For an unused domain it checks readiness for a new site.

For an existing managed domain it additionally reports:

- site name
- database
- project path
- HTTP port
- Socket port
- backup count
- latest backup ID
- latest backup timestamp
- latest checksum verification status
