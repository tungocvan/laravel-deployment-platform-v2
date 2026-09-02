#!/usr/bin/env bash
set -Eeuo pipefail
source "${PLATFORM_HOME:-/opt/laravel-deployment-platform-v2}/core/bootstrap.sh"

cat <<'EOF'
USAGE
  platform deploy <command> [options]

COMMANDS
  run <site|path>
      Full deploy:
      identity -> preflight -> Docker build -> up -> wait-db -> migrate -> optimize -> health

  prepare <site|path>
      identity -> preflight -> Docker build -> up -> wait-db

  frontend detect <site|path>
      Detect Laravel, Node/Vite, package manager and package scripts.

  frontend scripts <site|path>
      List scripts from package.json.

  frontend install <site|path>
      Install frontend dependencies.

  frontend build <site|path>
      Run production build (`<manager> run build`).

  identity <site|path>
  migrate <site|path>
  optimize <site|path>
  health <site|path>
      Run runtime, Laravel, public-storage and HTTP health checks.

  health <site|path> --storage-only
      Repair public storage permissions and verify Nginx can serve /storage/*.

  status <site|path>

OPTIONS
  --no-build
  --timeout=<seconds>

EXAMPLES
  platform deploy frontend detect nvh
  sudo platform deploy frontend install nvh
  sudo platform deploy frontend build nvh
  sudo platform deploy health nvh --storage-only
  sudo platform deploy run nvh
EOF
