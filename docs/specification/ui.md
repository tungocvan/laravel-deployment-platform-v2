# Interactive UI Specification v1.0 dev.6

## Deploy Wizard

The UI selects a site then queries:

```bash
platform-v2 deploy frontend detect <site>
```

It may display detected capabilities and invoke Deploy APIs.

UI MUST NOT run npm, pnpm or yarn directly.

Frontend actions:

```text
Production Build       -> deploy frontend build
Install Dependencies   -> deploy frontend install
Show package scripts   -> deploy frontend scripts
```

Backend/full deploy continue using the existing Deploy API.
