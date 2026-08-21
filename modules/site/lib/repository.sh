#!/usr/bin/env bash

site_canonical_repo() {
  printf '%s' 'git@github.com:tungocvan/laravel-shop.git'
}

site_default_repo() {
  printf '%s' "${PLATFORM_DEFAULT_SITE_REPO:-$(site_canonical_repo)}"
}
