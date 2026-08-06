#!/usr/bin/env bash
#
# Applies the shared dev schema to the Firebird 2.5 container.
#
# The FB 5 image seeds itself through /docker-entrypoint-initdb.d; this
# image has no such hook, so the schema goes in here instead. Sourced
# from the FB 5 directory rather than copied, so the two engines are
# always tested against the identical schema — a divergence between them
# would silently invalidate every version-gating comparison.
#
# Safe to re-run: it checks whether the schema is already present and
# exits without touching an existing database.
set -euo pipefail

CONTAINER=plamenix-firebird25
DB=/firebird/data/test.fdb
SCHEMA="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../firebird5/init/01-schema.sql"

if [ ! -f "$SCHEMA" ]; then
  echo "shared schema not found at $SCHEMA" >&2
  exit 1
fi

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "container $CONTAINER is not running — start it with 'docker compose up -d'" >&2
  exit 1
fi

echo "waiting for $CONTAINER to report healthy (emulated, this is slow)…"
for _ in $(seq 1 60); do
  status="$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null || echo unknown)"
  [ "$status" = "healthy" ] && break
  sleep 5
done
if [ "$(docker inspect --format '{{.State.Health.Status}}' "$CONTAINER")" != "healthy" ]; then
  echo "container never became healthy; check 'docker logs $CONTAINER'" >&2
  exit 1
fi

existing="$(docker exec -i "$CONTAINER" /usr/local/firebird/bin/isql -u SYSDBA -p masterkey "$DB" <<'SQL' 2>/dev/null | tr -dc '0-9'
SET HEADING OFF;
SELECT COUNT(*) FROM rdb$relations WHERE rdb$system_flag = 0;
SQL
)"

if [ "${existing:-0}" -gt 0 ]; then
  echo "schema already present (${existing} user relations) — nothing to do"
  exit 0
fi

echo "applying shared schema…"
docker exec -i "$CONTAINER" /usr/local/firebird/bin/isql -u SYSDBA -p masterkey "$DB" < "$SCHEMA"

count="$(docker exec -i "$CONTAINER" /usr/local/firebird/bin/isql -u SYSDBA -p masterkey "$DB" <<'SQL' 2>/dev/null | tr -dc '0-9'
SET HEADING OFF;
SELECT COUNT(*) FROM rdb$relations WHERE rdb$system_flag = 0;
SQL
)"
echo "done — ${count} user relations on Firebird 2.5 at 127.0.0.1:3051"
