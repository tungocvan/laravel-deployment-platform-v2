#!/usr/bin/env bash

acquire_lock() {
  local lock_file="$1"
  mkdir -p "$(dirname "$lock_file")"
  exec 9>"$lock_file"
  flock -n 9 || die "Một tiến trình khác đang chạy."
}
