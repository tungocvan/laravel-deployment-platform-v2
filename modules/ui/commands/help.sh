#!/usr/bin/env bash
set -Eeuo pipefail
cat <<'EOF'
USAGE
  platform menu
  platform ui

DESCRIPTION
  Interactive Bash UI over existing Platform commands.

FEATURES
  Site management
  Backup / Restore
  Deploy
  Doctor
  Nginx / SSL
  Packages

The UI is a frontend only. Existing CLI commands remain unchanged.
EOF
