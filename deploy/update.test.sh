#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/bin"
cat > "$work/bin/docker" <<'MOCK'
#!/bin/sh
printf '%s %s\n' "$WEWE_RSS_IMAGE" "$*" >> "$MOCK_LOG"
case "$*" in
  'compose '*' ps -q app') echo app-id;;
  'compose '*' ps -q db') echo db-id;;
  'inspect app-id --format {{.Image}}') echo sha256:old;;
  'image inspect sha256:old') [ "${MOCK_MISSING_OLD:-0}" = 0 ];;
  'compose '*' pull app') [ "${MOCK_PULL_FAIL:-0}" = 0 ];;
  'inspect app-id --format '* ) echo "${MOCK_HEALTH:-healthy}";;
  'exec db-id '*) echo '-- database backup';;
esac
MOCK
printf '#!/bin/sh\nexit 0\n' > "$work/bin/sleep"
chmod +x "$work/bin/docker" "$work/bin/sleep"
export PATH="$work/bin:$PATH"
image=ghcr.io/example/rss@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
for scenario in success missing-old pull-fail unhealthy local; do
  mkdir "$work/$scenario"
  cd "$work/$scenario"
  printf 'AUTH_CODE=private-test-value\nWEWE_RSS_IMAGE=previous\n' > .env.production
  touch docker-compose.production.yml
  export MOCK_LOG="$work/$scenario/log"
  export MOCK_MISSING_OLD=0 MOCK_PULL_FAIL=0 MOCK_HEALTH=healthy
  case "$scenario" in
    local) image=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;;
    missing-old) MOCK_MISSING_OLD=1;;
    pull-fail) MOCK_PULL_FAIL=1;;
    unhealthy) MOCK_HEALTH=unhealthy;;
  esac
  if sh "$root/deploy/update.sh" "$image" > output 2>&1; then
    [ "$scenario" = success ] || [ "$scenario" = local ]
    if [ "$scenario" = local ] && grep -q " pull app" "$MOCK_LOG"; then exit 1; fi
    grep -q "WEWE_RSS_IMAGE=$image" .env.production
    grep -q 'AUTH_CODE=private-test-value' .env.production
    test -s backups/*/database.sql
  else
    if [ "$scenario" = success ]; then cat output; cat "$MOCK_LOG"; exit 1; fi
    [ "$scenario" != success ]
    grep -q 'WEWE_RSS_IMAGE=previous' .env.production
    case "$scenario" in
      unhealthy) grep -q 'sha256:old compose .* up -d --no-build --no-deps app' "$MOCK_LOG";;
      *) if grep -q ' up ' "$MOCK_LOG"; then exit 1; fi;;
    esac
  fi
  if grep -q 'private-test-value' output; then exit 1; fi
  echo "$scenario: passed"
done
