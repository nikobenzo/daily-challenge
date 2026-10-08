#!/usr/bin/env bash
# Disposable PostgreSQL policy tests; no Docker, hosted credentials, or network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for tool in initdb pg_ctl psql; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
WORK="$(mktemp -d /tmp/daily-challenge-pg.XXXXXX)"
STARTED=0
cleanup() {
  if [[ "$STARTED" == 1 ]]; then
    pg_ctl -D "$WORK/data" -m immediate -w stop >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT
initdb -D "$WORK/data" -U postgres --auth=trust --no-locale --encoding=UTF8 >"$WORK/init.log" 2>&1
mkdir "$WORK/socket"
# Trust authentication is confined to a private temporary Unix socket; no TCP.
pg_ctl -D "$WORK/data" -l "$WORK/server.log" \
  -o "-k $WORK/socket -p 55439 -c listen_addresses=''" -w start >/dev/null
STARTED=1
PSQL=(psql -X -h "$WORK/socket" -p 55439 -U postgres -d postgres -v ON_ERROR_STOP=1)
# Minimal stand-in for Supabase roles/auth schema. Real hosted auth is tested
# separately with real sessions; this verifies PostgreSQL grants and RLS only.
"${PSQL[@]}" <<'SQL'
create role anon nologin;
create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')::uuid
$$;
grant usage on schema public, auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
SQL
for migration in "$ROOT"/supabase/migrations/*.sql; do
  "${PSQL[@]}" -f "$migration"
done
for test in "$ROOT"/supabase/tests/*.sql; do
  "${PSQL[@]}" -f "$test"
done
