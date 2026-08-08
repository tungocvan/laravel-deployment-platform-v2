# Modular Architecture

## Core

`core/` không chứa nghiệp vụ site/deploy/database. Core chỉ cung cấp:

- dispatcher
- config
- logging
- locking
- JSON helpers
- module discovery

## Module

Mỗi module là một bounded context:

```text
modules/site/
├── commands/
├── lib/
├── docs/
└── tests/
```

## Dispatch

```text
platform site create
→ core dispatcher
→ modules/site/commands/create.sh
→ modules/site/lib/site.sh
```
