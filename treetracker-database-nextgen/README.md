# treetracker-database-nextgen

Baseline schema for the local (k3s) Treetracker database, captured from the **online nextgen dev
database** rather than rebuilt from the legacy `treetracker-database` seed + migrations.

## Why this exists
The legacy `treetracker-database/main` path (a partial `treetracker_seed.pgsql` + 172 db-migrate
migrations) does **not** rebuild cleanly from empty: the seed ships `pre-data + data` only (no primary
keys / foreign keys / indexes), and the tail of the migrations depends on an out-of-band region/geo
materialized-view subsystem. Instead, we take the **real dev schema** — which already has every
constraint, index and FK — as the authoritative baseline.

Source DB: `db-postgresql-sfo2-nextgen-do-user-1067699-0.db.ondigitalocean.com:25060/treetracker`
(PostgreSQL 17). This repo currently captures the **`public`** schema (trees, planter, … — what the
capture→verify path and `treetracker-admin-api` read/write). Other schemas (`field_data`, `keycloak`,
`wallet`, …) are provisioned by their own services/migrations, not from here.

## How init works (db-migrate)
The DB is built by **db-migrate**, not by running SQL directly — so it's versioned and future schema
changes are just new migrations. The **first migration** loads the online-schema baseline:
- `migrations/20260705000000-baseline-public-schema.js` → runs `migrations/sqls/…-up.sql`
- that SQL = the sanitized `public` dump (psql `\restrict`/`\unrestrict` and PG17-only
  `SET transaction_timeout` stripped; the `search_path=''` reset removed so db-migrate can write its
  tracking table; extensions + non-public schemas prepended so a fresh DB works).
- db-migrate tracks state in **`nextgen_migrations`** (via `-t`), NOT the default `migrations`
  (the dump ships its own legacy `public.migrations` table).

```bash
npm install
npm run migrate:up      # db-migrate up -e local -t nextgen_migrations
```
`database.json` → local env `127.0.0.1:5432` (port-forward the k3d Postgres first).

## Contents
- `schema/public-schema.sql` — raw `pg_dump --schema-only --no-owner --no-privileges -n public`
  (122 tables, ~257 constraints/indexes). Source snapshot; the sanitized copy lives in the migration.

## Regenerate the dump
```bash
export PATH="$(brew --prefix libpq)/bin:$PATH"
CONN='postgresql://<user>:<pw>@db-postgresql-sfo2-nextgen-do-user-1067699-0.db.ondigitalocean.com:25060/treetracker?sslmode=require'
pg_dump "$CONN" --schema-only --no-owner --no-privileges -n public -f schema/public-schema.sql
```

## Load into the local k3d Postgres (namespace `data`, DB `treetracker`)
```bash
./load.sh    # resets the treetracker DB, creates extensions/schemas, loads schema/public-schema.sql
```
Loads cleanly into local PostgreSQL 15 (the two PG17→15 notices — `transaction_timeout` SET and
`CREATE SCHEMA public` — are harmless).
