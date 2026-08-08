#!/usr/bin/env bash
set -Eeuo pipefail

status=0
while IFS= read -r -d '' file; do
  bash -n "$file" || status=1
done < <(find bin core modules migration tests tools -type f -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
  find bin core modules migration tests tools -type f -name '*.sh' -print0     | xargs -0 shellcheck || status=1
fi

exit "$status"
