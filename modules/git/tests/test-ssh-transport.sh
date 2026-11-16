#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
[[ "$1" == "-G" ]] || exit 2
case "$2" in
  github-acme|github-acme-shop) printf 'hostname github.com\nuser git\nidentitiesonly yes\n' ;;
  *) printf 'hostname %s\n' "$2" ;;
esac
MOCK
cat > "$TMP/bin/git" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_LOG"
if [[ "$1" == ls-remote ]]; then
  case "$2" in
    git@github.com:acme/shop.git) [[ "${MOCK_CANONICAL_OK:-0}" == 1 ]] ;;
    git@github-acme:acme/shop.git) [[ "${MOCK_OWNER_OK:-0}" == 1 ]] ;;
    git@github-acme-shop:acme/shop.git) [[ "${MOCK_REPO_OK:-0}" == 1 ]] ;;
    *) exit 1 ;;
  esac
  exit $?
fi
exit 0
MOCK
chmod +x "$TMP/bin/ssh" "$TMP/bin/git"
export PATH="$TMP/bin:$PATH" MOCK_LOG="$TMP/git.log"
source "$ROOT/modules/git/lib/git.sh"
repo="git@github.com:acme/shop.git"
export MOCK_CANONICAL_OK=1 MOCK_OWNER_OK=0 MOCK_REPO_OK=0
[[ "$(platform_git_resolve_read_url "$repo")" == "$repo" ]]
export MOCK_CANONICAL_OK=0 MOCK_OWNER_OK=1
[[ "$(platform_git_resolve_read_url "$repo")" == "git@github-acme:acme/shop.git" ]]
export MOCK_OWNER_OK=0 MOCK_REPO_OK=1
[[ "$(platform_git_resolve_read_url "$repo")" == "git@github-acme-shop:acme/shop.git" ]]
export MOCK_REPO_OK=0
if platform_git_resolve_read_url "$repo" >/dev/null; then
  echo "[FAIL] inaccessible GitHub repo must fail closed" >&2
  exit 1
fi
[[ "$(platform_git_resolve_read_url 'git@example.org:acme/shop.git')" == 'git@example.org:acme/shop.git' ]]
: > "$MOCK_LOG"
platform_git_transport "$repo" 'git@github-acme-shop:acme/shop.git' -C /tmp/site fetch --prune origin
grep -Fq 'url.git@github-acme-shop:acme/shop.git.insteadOf=git@github.com:acme/shop.git' "$MOCK_LOG"
grep -Fq 'fetch --prune origin' "$MOCK_LOG"
echo '[OK] SSH alias transport: canonical, owner fallback, repository fallback, deny, scoped rewrite'
