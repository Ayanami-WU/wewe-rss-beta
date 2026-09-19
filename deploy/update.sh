#!/bin/sh
# Run in the deployment directory containing Compose and .env.production.
set -eu
umask 077
image=${1:?Usage: sh update.sh ghcr.io/OWNER/IMAGE@sha256:DIGEST}
case "$image" in ghcr.io/*@sha256:*) ;; *) echo 'An immutable GHCR digest is required' >&2; exit 1;; esac
digest=${image##*@sha256:}
[ ${#digest} -eq 64 ] || exit 1
case "$digest" in *[!0-9a-f]*) exit 1;; esac
export WEWE_RSS_IMAGE="$image"
compose() { docker compose -p wewe-rss-beta --env-file .env.production -f docker-compose.production.yml "$@"; }
compose config --quiet
container=$(compose ps -q app)
db=$(compose ps -q db)
[ -n "$container" ] && [ -n "$db" ] || { echo 'Existing RSS app and database required' >&2; exit 1; }
old_image=$(docker inspect "$container" --format '{{.Image}}')
docker image inspect "$old_image" >/dev/null || { echo 'Restore a rollback image before updating' >&2; exit 1; }
# No source tree, build command, package installation, or database recreation.
compose pull app
stamp=$(date -u +%Y%m%dT%H%M%SZ)
backup_dir="backups/$stamp"
mkdir -p "$backup_dir"
docker tag "$old_image" "wewe-rss-beta:rollback-$stamp"
cp .env.production "$backup_dir/env.production"
docker exec "$db" sh -c 'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" exec mysqldump -u root --single-transaction --no-tablespaces wewe-rss' > "$backup_dir/database.sql"
[ -s "$backup_dir/database.sql" ]
rollback() {
  echo "Update failed; restoring application image $old_image" >&2
  export WEWE_RSS_IMAGE="$old_image"
  compose up -d --no-build --no-deps app
  # Schema rollback is never automatic; retain the database backup.
}
if ! compose up -d --no-build --no-deps app; then rollback; exit 1; fi
attempt=0
while [ "$attempt" -lt 30 ]; do
  container=$(compose ps -q app)
  if [ -n "$container" ] && [ "$(docker inspect "$container" --format '{{if .State.Health}}{{.State.Health.Status}}{{end}}')" = healthy ]; then
    # Persist the exact image only after health succeeds.
    sed '/^WEWE_RSS_IMAGE=/d' .env.production > .env.production.next
    printf 'WEWE_RSS_IMAGE=%s\n' "$image" >> .env.production.next
    mv .env.production.next .env.production
    printf 'Deployed %s; backup: %s\n' "$image" "$backup_dir"
    exit 0
  fi
  attempt=$((attempt + 1))
  sleep 3
done
rollback
exit 1
