#!/usr/bin/env bash
# Database readiness uses Docker health status only.
# Application database credentials are validated by Laravel migrate afterwards.

deploy_wait_database() {
  local project_dir="$1" timeout="${2:-120}"
  local started now container_id status
  started="$(date +%s)"

  while true; do
    container_id="$(deploy_compose "$project_dir" ps -q db 2>/dev/null | head -n1 || true)"
    status=""

    if [[ -n "$container_id" ]]; then
      status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"
      if [[ "$status" == "healthy" || "$status" == "running" ]]; then
        echo "[OK] Database service ready ($status)"
        return 0
      fi
    fi

    now="$(date +%s)"
    if (( now - started >= timeout )); then
      echo "[ERROR] Database readiness detail: container=${container_id:-missing}, status=${status:-unknown}" >&2
      die "Timeout chờ database (${timeout}s)."
    fi
    sleep 2
  done
}
