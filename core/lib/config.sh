#!/usr/bin/env bash

load_platform_config() {
  local config_file="${PLATFORM_CONFIG:-$PLATFORM_HOME/config/platform.env}"
  if [[ -f "$config_file" ]]; then
    set -a
    source "$config_file"
    set +a
  fi
}
