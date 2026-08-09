#!/usr/bin/env bash
set -Eeuo pipefail

status=0
while IFS= read -r -d '' file; do
  bash -n "$file" || status=1
done < <(find bin core modules migration tests tools -type f -name '*.sh' -print0)

if command -v shellcheck >/dev/null 2>&1; then
  # Syntax always blocks. ShellCheck blocks only error-severity findings so
  # CI and VPS do not disagree because of existing warning/info debt.
  find bin core modules migration tests tools -type f -name '*.sh' -print0 \
    | xargs -0 shellcheck --severity=error || status=1
fi

exit "$status"
