# Local k3s backend — setup runbook

How to build the local Greenstand backend (for the Android capture→verify e2e) from scratch: a k3d
cluster running PostgreSQL, the db-migrate-managed schemas, RabbitMQ, and the treetracker-field-data
service. Everything runs in the **`k3d-greenstand`** cluster; nothing here touches the real cloud
clusters.

## Quick start (scripts)
```bash
./k3s/prepare.sh     # ONCE per machine (macOS-specific): install tools + fix Docker proxy.
                     #   Re-run if your LAN IP changes (docker pulls start failing).
./k3s/up.sh          # portable, idempotent: bring up the whole stack. Re-run to repair/continue.
                     #   single step: ./k3s/up.sh postgres | migrate | rabbitmq | field_data | ...
./k3s/down.sh        # tear down: delete the k3d cluster (all pods + data).
                     #   ./k3s/down.sh --namespaces   (keep cluster, drop stack namespaces)
                     #   ./k3s/down.sh --images        (also remove built/pulled images)
```
`prepare.sh` = your-machine-specific bootstrap (Homebrew installs, ClashX/Docker proxy). `up.sh` = pure
stack setup, same for local (`ENV=local`, k3d) and cloud CI (`ENV=ci KUBE_CONTEXT=… IMAGE_REGISTRY=…`).
The sections below document what those scripts do, step by step.

> ⚠️ **Context safety:** the kube context often reverts to the real dev cluster
> `do-sfo2-dev-k8s-treetracker` across sessions. Before ANY `kubectl`/`apply`/`exec`, run
> `kubectl config use-context k3d-greenstand` and assert it. Every command below assumes:
> ```bash
> export PATH="/opt/homebrew/bin:$PATH"
> export NO_PROXY="0.0.0.0,127.0.0.1,localhost,::1,.svc,.cluster.local" no_proxy="$NO_PROXY"
> kubectl config use-context k3d-greenstand
> ```
> `NO_PROXY` is required because the shell inherits `http_proxy` (ClashX); without it kubectl routes the
> localhost API call through the proxy and fails.

---

## 0. Toolchain (one-time)
```bash
brew install k3d helm awscli libpq
brew link --force libpq         # puts psql/pg_dump on PATH (keg-only otherwise)
# Docker Desktop installed; Node via nvm (v24 used here)
```

## 1. Internet proxy (this machine has no direct internet)
Host uses ClashX at `127.0.0.1:7890`.
- Shell tools: `export https_proxy=http://127.0.0.1:7890 http_proxy=http://127.0.0.1:7890 all_proxy=socks5://127.0.0.1:7890`
- **Docker image pulls** (daemon runs in Docker Desktop's VM, can't reach host loopback):
  1. In ClashX enable **“Allow connections from LAN”** (binds `0.0.0.0:7890`).
  2. Point Docker's daemon proxy at the Mac's LAN IP (manual mode):
     ```bash
     IP=$(ipconfig getifaddr "$(route -n get default | awk '/interface:/{print $2}')")
     # settings-store.json: ProxyHTTPMode=manual, OverrideProxyHTTP/HTTPS=http://$IP:7890
     ```
     File: `~/Library/Group Containers/group.com.docker/settings-store.json`; restart Docker after.
  3. **When the Mac's IP changes (DHCP), redo step 2** — else `docker pull` → "network is unreachable".
- Raw TCP (e.g. Postgres :25060 to the online DB) works directly, no proxy needed.

## 2. Create the k3d cluster
```bash
k3d cluster create greenstand \
  --k3s-arg "--disable=traefik@server:*" \
  -p "8088:80@loadbalancer" -p "8443:443@loadbalancer" --agents 0
# after a Docker/machine restart the cluster is stopped, not gone:
k3d cluster start greenstand
```
In-cluster containerd does NOT use the proxy → **pull images on the host, then import**:
```bash
docker pull <image> && k3d image import <image> -c greenstand
```

## 3. PostgreSQL
```bash
kubectl apply -f k3s/postgres.yaml           # postgis/postgis:15-3.4, ns=data, DB=treetracker (postgres/postgres)
kubectl -n data rollout status deploy/postgres
# second database:
POD=$(kubectl -n data get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')
kubectl -n data exec "$POD" -- psql -U postgres -d postgres -c "CREATE DATABASE data_pipeline;"
```
Port-forward for host-side db-migrate (keep running in a second terminal):
```bash
kubectl -n data port-forward svc/postgres 5432:5432
```

## 4. Schemas via db-migrate (repo: `treetracker-database-nextgen`)
Baselined from the online dev DB; each DB is its own db-migrate project, first migration = the schema
baseline, tracking table `nextgen_migrations`. See that repo's README for details.
```bash
cd treetracker-database-nextgen/treetracker    && npm install && npm run migrate:up   # public (122 tables incl. trees/planter)
cd ../data_pipeline                            && npm install && npm run migrate:up   # data_pipeline.bulk_tree_upload
```

## 5. field_data schema (repo: `treetracker-field-data`, its own migrations)
`field_data` is a schema **inside the `treetracker` DB**, created by field-data's own 23 migrations.
```bash
# treetracker-field-data/database/database.json  → env "local": host 127.0.0.1:5432, db treetracker,
#                                                    user/pw postgres, "schema": "field_data"
cd treetracker-field-data/database
../../treetracker-database-nextgen/treetracker/node_modules/.bin/db-migrate up -e local
# → field_data.raw_capture, session, track, wallet_registration, device_configuration, domain_event*
```

## 6. RabbitMQ (field-data publishes raw-capture-created)
```bash
docker pull rabbitmq:3.13-management && k3d image import rabbitmq:3.13-management -c greenstand
kubectl apply -f k3s/rabbitmq.yaml           # ns=rabbitmq, svc rabbitmq.rabbitmq.svc:5672 (guest/guest)
```

## 7. treetracker-field-data service
Build the image, import it, deploy the local kustomize overlay (reuses the repo's base; swaps
sealed-secrets → plain local Secrets, drops the Ambassador Mapping / migration Job / RBAC, `:local`
image, 1 replica, no DO node-affinity):
```bash
cd treetracker-field-data
docker build -t treetracker-field-data:local .
k3d image import treetracker-field-data:local -c greenstand
kubectl apply -k deployment/overlays/local
kubectl -n field-data-api rollout status deploy/treetracker-field-data
```
- Env (both DB URLs → the one `treetracker` DB; field_data via `DATABASE_SCHEMA`, public.trees via the
  legacy connection): `DATABASE_URL` + `DATABASE_URL_LEGACYDB` = `database-connection/db`,
  `RABBIT_MQ_URL` = `rabbitmq-connection/messageQueue`. HTTP :3006, Service exposes **:80→3006**
  at `treetracker-field-data.field-data-api.svc`.
- Healthy log: `setting a schema` / `listening on port:3006`.

---

## Status / still to do
Done: cluster, Postgres (+ `treetracker`, `data_pipeline`, `field_data`), RabbitMQ, field-data,
bulk-pack-transformer-v2, bulk-pack-processor (CronJob).
**Skipped:** `treetracker-data-pipeline` consumer (SQS→`bulk_tree_upload`) — its old `pg@7.18` client
hangs on the PostgreSQL 15 SCRAM handshake. For the e2e, feed `bulk_tree_upload` another way (direct
insert, or revisit with `pg@8` / md5 auth).
Next: **admin-api + admin-client** (legacy user system — username/password + `JWT_SECRET`, **no
Keycloak**; seed a legacy admin user for the `/verify` login), then run `apps/e2e` `03_capture_setup`.
