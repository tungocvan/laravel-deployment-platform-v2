#!/usr/bin/env bash

doctor_site_service_state() {
  local project_dir="$1" service="$2" output
  output="$(deploy_compose "$project_dir" ps "$service" 2>/dev/null || true)"
  if [[ -z "$output" ]]; then
    printf 'missing\n'
  elif grep -Eqi 'unhealthy|Exited|Restarting|dead' <<<"$output"; then
    printf 'unhealthy\n'
  elif grep -Eqi 'healthy|Up|running' <<<"$output"; then
    printf 'healthy\n'
  else
    printf 'unknown\n'
  fi
}

doctor_site() {
  local key="${1:-}"
  [[ -n "$key" ]] || platform_die "$PLATFORM_EXIT_USAGE" "DOCTOR.ARGUMENT_REQUIRED" "USAGE: platform-v2 doctor site <site>"

  local site_json
  site_json="$(inventory_find_json "$key" 2>/dev/null || true)"
  [[ -n "$site_json" ]] || platform_die "$PLATFORM_EXIT_VALIDATION" "DOCTOR.SITE_NOT_FOUND" "Không tìm thấy managed site trong Inventory: $key"

  local name domain path inventory_repo inventory_branch inventory_commit
  name="$(doctor_json_field "$site_json" name)"
  domain="$(doctor_json_field "$site_json" domain)"
  path="$(doctor_json_field "$site_json" path)"
  inventory_repo="$(doctor_json_field "$site_json" repo)"
  inventory_branch="$(doctor_json_field "$site_json" branch)"
  inventory_commit="$(doctor_json_field "$site_json" commit)"

  local errors=0 warnings=0
  echo "========================================================="
  echo "Laravel Deployment Platform — Site Doctor"
  echo "========================================================="
  echo "Site       : ${name:-$key}"
  echo "Domain     : ${domain:-N/A}"
  echo "Path       : ${path:-N/A}"
  echo

  echo "----- SOURCE -----"
  if [[ -n "$path" && -d "$path" ]]; then
    doctor_ok "Project path tồn tại."
  else
    doctor_err "Project path không tồn tại: ${path:-<empty>}"
    errors=$((errors+1))
  fi

  if [[ -n "$path" && -f "$path/artisan" && -f "$path/composer.json" ]]; then
    doctor_ok "Laravel source markers hợp lệ."
  else
    doctor_err "Thiếu artisan/composer.json."
    errors=$((errors+1))
  fi

  if [[ -n "$path" && -d "$path/.git" ]]; then
    platform_git_trust "$path"
    local actual_repo actual_branch actual_commit dirty
    actual_repo="$(git -C "$path" remote get-url origin 2>/dev/null || true)"
    actual_branch="$(git -C "$path" branch --show-current 2>/dev/null || true)"
    actual_commit="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
    dirty="$(git -C "$path" status --porcelain --untracked-files=all 2>/dev/null || true)"

    [[ -n "$actual_repo" ]] && doctor_ok "Git origin: $actual_repo" || { doctor_err "Git origin missing."; errors=$((errors+1)); }
    [[ -n "$actual_branch" ]] && doctor_ok "Git branch: $actual_branch" || { doctor_err "Detached/unknown Git branch."; errors=$((errors+1)); }
    [[ -n "$actual_commit" ]] && doctor_ok "Git HEAD: $actual_commit" || { doctor_err "Không đọc được Git HEAD."; errors=$((errors+1)); }

    if [[ -n "$inventory_repo" && "$actual_repo" != "$inventory_repo" ]]; then
      doctor_warn "Inventory repo stale: $inventory_repo"
      warnings=$((warnings+1))
    fi
    if [[ -n "$inventory_branch" && "$actual_branch" != "$inventory_branch" ]]; then
      doctor_warn "Inventory branch stale: $inventory_branch"
      warnings=$((warnings+1))
    fi
    if [[ -n "$inventory_commit" && "$actual_commit" != "$inventory_commit" ]]; then
      doctor_warn "Inventory commit stale: $inventory_commit"
      warnings=$((warnings+1))
    fi
    if [[ -n "$dirty" ]]; then
      doctor_warn "Git working tree có thay đổi/untracked files."
      printf '%s\n' "$dirty" | sed 's/^/       /'
      warnings=$((warnings+1))
    else
      doctor_ok "Git working tree sạch."
    fi
  else
    doctor_err "Project không có Git working tree."
    errors=$((errors+1))
  fi

  echo
  echo "----- RUNTIME -----"
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    doctor_ok "Docker daemon hoạt động."
  else
    doctor_err "Docker daemon không sẵn sàng."
    errors=$((errors+1))
  fi

  if [[ -n "$path" && -d "$path" ]]; then
    local service state
    for service in db redis app socket web; do
      state="$(doctor_site_service_state "$path" "$service")"
      if [[ "$state" == "healthy" ]]; then
        doctor_ok "service $service: healthy/running"
      else
        doctor_err "service $service: $state"
        errors=$((errors+1))
      fi
    done

    for service in queue queue-admission-documents scheduler; do
      state="$(doctor_site_service_state "$path" "$service")"
      if [[ "$state" == "healthy" ]]; then
        doctor_ok "worker $service: healthy/running"
      elif [[ "$state" == "missing" ]]; then
        doctor_info "worker $service: not configured/running"
      else
        doctor_warn "worker $service: $state"
        warnings=$((warnings+1))
      fi
    done
  fi

  echo
  echo "----- BACKUP -----"
  doctor_backup_info "${name:-$key}"

  echo
  echo "========================================================="
  echo "RESULT"
  echo "========================================================="
  if [[ "$errors" -eq 0 ]]; then
    echo "[READY] Site doctor không phát hiện blocker."
    [[ "$warnings" -gt 0 ]] && echo "[WARN] Có $warnings cảnh báo cần review."
    return 0
  fi

  echo "[NOT READY] Site doctor phát hiện $errors blocker."
  [[ "$warnings" -gt 0 ]] && echo "[WARN] Có thêm $warnings cảnh báo."
  return 1
}
