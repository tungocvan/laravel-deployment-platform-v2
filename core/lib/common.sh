#!/usr/bin/env bash

info()    { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
success() { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn()    { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
error()   { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()     { error "$*"; exit 1; }

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Command này cần sudo/root."
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Thiếu command: $1"
}

confirm() {
  local answer
  read -r -p "${1:-Tiếp tục?} [y/N]: " answer
  [[ "$answer" =~ ^[Yy]$ ]]
}
