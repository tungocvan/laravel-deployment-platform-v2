# Nginx Module

## Layout

```text
/etc/nginx/sites-available/<domain>
/etc/nginx/sites-enabled/<domain> -> sites-available/<domain>
```

The Platform uses domain names as config filenames.

## Conflict policy

A config declaring the requested `server_name` anywhere in `sites-available` is a conflict unless it is the exact target file.

Existing non-Platform configs are never silently overwritten.
