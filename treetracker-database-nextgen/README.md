# treetracker-database-nextgen

db-migrate-managed schemas for the **local (k3s) Treetracker databases**, baselined from the **online
nextgen dev cluster** rather than rebuilt from the legacy `treetracker-database` seed + migrations.

## Why this exists
The legacy `treetracker-database/main` path (a partial `treetracker_seed.pgsql` + 172 db-migrate
migrations) does **not** rebuild cleanly from empty: the seed ships `pre-data + data` only (no primary
keys / foreign keys / indexes), and the tail of the migrations depends on an out-of-band region/geo
materialized-view subsystem. Instead we take the **real dev schema** — which already has every
constraint, index and FK — as the authoritative baseline, captured schema-only.

Source cluster: `db-postgresql-sfo2-nextgen-do-user-1067699-0.db.ondigitalocean.com:25060` (PostgreSQL 17).
That cluster has 10 databases; we mirror the two the capture→verify pipeline needs as **separate local
databases** (matching prod topology, not schemas-in-one-DB).

## Layout — one db-migrate project per database
Mirrors the real `treetracker-database` repo's `main/` + `pipeline/` split.

| Dir | Local DB | First migration (baseline) | Key objects |
|---|---|---|---|
| `treetracker/` | `treetracker` | `…-baseline-public-schema` | `public` schema — 122 tables incl. `trees`, `planter` (admin `/verify` + legacy-tree target) |
| `data_pipeline/` | `data_pipeline` | `…-baseline-data-pipeline-schema` | `public.bulk_tree_upload` (capture-upload staging the consumer writes) + `pipeline` schema |

(Keycloak uses its own `keycloak` DB, provisioned by Keycloak itself — not managed here.)

## How init works (db-migrate)
Each DB is built by **db-migrate**, not by running SQL directly — versioned, and future schema changes
are just new migrations. The **first migration** in each project loads its online-schema baseline via
`db.runSql(<sanitized dump>)`. The committed `migrations/sqls/*-up.sql` is the single source of truth.

State is tracked in **`nextgen_migrations`** (via `-t`), NOT the default `migrations` (the dumps ship
their own legacy `public.migrations` table).

The dumps are sanitized for driver execution (pg driver, not psql): strip psql `\restrict`/`\unrestrict`,
strip PG17-only `SET transaction_timeout`, remove `set_config('search_path','')` (else db-migrate can't
write its tracking table), make `CREATE SCHEMA` idempotent, and prepend extensions + non-public schemas
so a fresh DB works.

## Init a database
Port-forward the k3d Postgres first (`kubectl -n data port-forward svc/postgres 5432:5432`), ensure the
target DB exists (`CREATE DATABASE treetracker` / `data_pipeline`), then:
```bash
cd treetracker      # or: cd data_pipeline
npm install
npm run migrate:up  # db-migrate up -e local -t nextgen_migrations
```
Both `database.json`s point at local env `127.0.0.1:5432`. Loads cleanly into local PostgreSQL 15.

## Refresh a baseline from the online DB
Re-dump schema-only and re-sanitize into that project's `migrations/sqls/*-up.sql` (raw dumps aren't kept):
```bash
CONN='postgresql://<user>:<pw>@db-postgresql-sfo2-nextgen-do-user-1067699-0.db.ondigitalocean.com:25060/<db>?sslmode=require'
pg_dump "$CONN" --schema-only --no-owner --no-privileges -n public -f /tmp/dump.sql
# then sanitize as above
```
