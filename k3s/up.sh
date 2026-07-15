#!/usr/bin/env bash
#
# up.sh — set up the whole Greenstand capture→verify backend on a k8s cluster. PURE / portable:
# no host-tool installs and no proxy fiddling (that's prepare.sh, run once on your local machine).
# Idempotent + readiness-gated: re-running repairs/continues rather than duplicating.
#
# Env (same script for local dev and cloud CI e2e):
#   ENV=local (default) — k3d on this machine; images via `k3d image import`
#   ENV=ci               — existing kube-context (KUBE_CONTEXT); images pushed to $IMAGE_REGISTRY
#
# Usage:
#   ./k3s/up.sh                 # all steps
#   ./k3s/up.sh postgres        # one step (cluster|infra_images|postgres|migrate|rabbitmq|field_data|...)
#
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ENV="${ENV:-local}"
CLUSTER="${CLUSTER:-greenstand}"
CONTEXT="${KUBE_CONTEXT:-k3d-$CLUSTER}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"          # ci: registry to push to; empty ⇒ k3d image import
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
K3S_DIR="$ROOT/k3s"
NEXTGEN="$ROOT/treetracker-database-nextgen"
ADMIN_CLIENT="$ROOT/treetracker-admin-client"
ADMIN_CLIENT_PORT="${ADMIN_CLIENT_PORT:-3001}"   # host port-forward → admin-client pod (ADMIN_URL for the e2e)

export PATH="/opt/homebrew/bin:$PATH"
export NO_PROXY="0.0.0.0,127.0.0.1,localhost,::1,.svc,.cluster.local"
export no_proxy="$NO_PROXY"
command -v psql >/dev/null 2>&1 || PATH="$(brew --prefix libpq 2>/dev/null)/bin:$PATH"
if ! command -v node >/dev/null 2>&1; then
  for d in "$HOME"/.nvm/versions/node/*/bin; do [ -x "$d/node" ] && PATH="$d:$PATH" && break; done
fi

# ── Helpers ─────────────────────────────────────────────────────────────────
c_grn=$'\033[32m'; c_red=$'\033[31m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
log()  { echo "${c_grn}▶${c_off} $*"; }
info() { echo "${c_dim}  $*${c_off}"; }
die()  { echo "${c_red}✖ $*${c_off}" >&2; exit 1; }

k()      { kubectl --context "$CONTEXT" "$@"; }
pg_pod() { k -n data get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}' 2>/dev/null; }

ensure_image() {   # pull on host (retry transient EOF) if absent, then load into cluster
  local img="$1" i
  if ! docker image inspect "$img" >/dev/null 2>&1; then
    for i in $(seq 1 10); do
      docker pull "$img" >/dev/null 2>&1 && break
      [ "$i" = 10 ] && die "docker pull $img failed — run ./k3s/prepare.sh (proxy)"
      info "pull $img: retry $i"; sleep 5
    done
  fi
  load_image "$img"
}
load_image() {
  local img="$1"
  if [ -n "$IMAGE_REGISTRY" ]; then
    docker tag "$img" "$IMAGE_REGISTRY/$img"; docker push "$IMAGE_REGISTRY/$img" >/dev/null
  else
    k3d image import "$img" -c "$CLUSTER" >/dev/null 2>&1 || die "k3d image import $img failed"
  fi
}
wait_pg_ready() {
  local pod i; pod="$(pg_pod)"; [ -n "$pod" ] || die "no postgres pod"
  for i in $(seq 1 60); do
    k -n data exec "$pod" -- pg_isready -U postgres -d treetracker >/dev/null 2>&1 && return 0; sleep 2
  done; die "postgres never ready"
}
psql_admin() { k -n data exec -i "$(pg_pod)" -- psql -U postgres "$@"; }

PF_PID=""
start_pf() {
  pkill -f "port-forward svc/postgres" 2>/dev/null || true; sleep 1
  k -n data port-forward svc/postgres 5432:5432 >/tmp/up-pf.log 2>&1 & PF_PID=$!
  local i; for i in $(seq 1 30); do
    PGPASSWORD=postgres psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -tAc 'select 1' >/dev/null 2>&1 && return 0; sleep 1
  done; die "port-forward to postgres never came up"
}
stop_pf() { [ -n "$PF_PID" ] && kill "$PF_PID" 2>/dev/null || true; PF_PID=""; }

npm_migrate() {   # $1 = db-migrate project dir with npm "migrate:up"
  ( cd "$1" && { [ -d node_modules ] || npm install --no-audit --no-fund >/dev/null 2>&1; } \
    && npm run migrate:up >/dev/null ) || die "migrate failed in $1"
}

# ── Steps ─────────────────────────────────────────────────────────────────
step_preflight() {   # CHECK only — never install/fix (that's prepare.sh)
  command -v docker >/dev/null 2>&1 || die "docker missing — run ./k3s/prepare.sh"
  docker info >/dev/null 2>&1 || die "Docker not running — run ./k3s/prepare.sh"
  command -v kubectl >/dev/null 2>&1 || die "kubectl missing — run ./k3s/prepare.sh"
  command -v node >/dev/null 2>&1 || die "node missing — run ./k3s/prepare.sh"
  command -v psql >/dev/null 2>&1 || die "psql missing — run ./k3s/prepare.sh"
  [ "$ENV" = local ] && { command -v k3d >/dev/null 2>&1 || die "k3d missing — run ./k3s/prepare.sh"; }
  return 0
}

step_cluster() {
  if [ "$ENV" != local ]; then
    k get nodes >/dev/null 2>&1 || die "context $CONTEXT unreachable"; log "using cluster $CONTEXT"; return 0
  fi
  log "k3d cluster '$CLUSTER'"
  if k3d cluster list 2>/dev/null | grep -q "^$CLUSTER "; then
    k3d cluster start "$CLUSTER" >/dev/null 2>&1 || true
  else
    k3d cluster create "$CLUSTER" --k3s-arg "--disable=traefik@server:*" \
      -p "8088:80@loadbalancer" -p "8443:443@loadbalancer" --agents 0
  fi
  kubectl config use-context "$CONTEXT" >/dev/null
  [ "$(kubectl config current-context)" = "$CONTEXT" ] || die "context is not $CONTEXT"
}

step_infra_images() { log "infra images"; ensure_image "postgis/postgis:15-3.4"; ensure_image "rabbitmq:3.13-management"; }

step_postgres() {
  log "postgres"
  k apply -f "$K3S_DIR/postgres.yaml" >/dev/null
  k -n data rollout status deploy/postgres --timeout=180s
  wait_pg_ready
  psql_admin -d postgres -tAc "select 1 from pg_database where datname='data_pipeline'" | grep -q 1 \
    || psql_admin -d postgres -c "CREATE DATABASE data_pipeline;" >/dev/null
  info "databases: treetracker, data_pipeline"
}

step_migrate() {
  log "db-migrate (treetracker, data_pipeline, field_data)"
  start_pf
  npm_migrate "$NEXTGEN/treetracker"       # public schema (+ field_data/data_pipeline/keycloak schemas)
  npm_migrate "$NEXTGEN/data_pipeline"     # bulk_tree_upload
  ( cd "$ROOT/treetracker-field-data/database" \
    && "$NEXTGEN/treetracker/node_modules/.bin/db-migrate" up -e local >/dev/null ) \
    || die "field_data migrate failed"
  stop_pf
  info "public.trees + field_data.raw_capture + data_pipeline.bulk_tree_upload ready"
}

step_rabbitmq() { log "rabbitmq"; k apply -f "$K3S_DIR/rabbitmq.yaml" >/dev/null; k -n rabbitmq rollout status deploy/rabbitmq --timeout=180s; }

step_field_data() {
  log "treetracker-field-data"
  docker build -t treetracker-field-data:local "$ROOT/treetracker-field-data" >/tmp/up-fielddata-build.log 2>&1 \
    || die "field-data image build failed (see /tmp/up-fielddata-build.log)"
  load_image "treetracker-field-data:local"
  k apply -k "$ROOT/treetracker-field-data/deployment/overlays/local" >/dev/null
  k -n field-data-api rollout status deploy/treetracker-field-data --timeout=180s
}

# ── TODO: remaining services (fill in as built) ─────────────────────────────
step_transformer_v2() {
  log "bulk-pack-transformer-v2"
  docker build -t bulk-pack-transformer-v2:local "$ROOT/bulk-pack-transformer-v2" >/tmp/up-btv2-build.log 2>&1 \
    || die "transformer-v2 image build failed (see /tmp/up-btv2-build.log)"
  load_image "bulk-pack-transformer-v2:local"
  k apply -k "$ROOT/bulk-pack-transformer-v2/deployment/overlays/local" >/dev/null
  k -n bulk-pack-services rollout status deploy/bulk-pack-transformer-v2 --timeout=180s
}
step_processor() {
  log "bulk-pack-processor (CronJob)"
  docker build -t bulk-pack-processor:local "$ROOT/bulk-pack-processor" >/tmp/up-bpp-build.log 2>&1 \
    || die "processor image build failed (see /tmp/up-bpp-build.log)"
  load_image "bulk-pack-processor:local"
  k apply -k "$ROOT/bulk-pack-processor/deployment/overlays/local" >/dev/null
  info "cronjob scheduled (*/5); trigger now: kubectl -n bulk-pack-services create job bpp-now --from=cronjob/bulk-pack-processor"
}
step_consumer()       { info "SKIPPED: treetracker-data-pipeline consumer (old pg@7.18 client hangs on the PG15 SCRAM handshake). Feed bulk_tree_upload another way for the e2e."; }
step_keycloak()       { info "SKIPPED: admin stack uses the legacy user system — no Keycloak needed"; }
step_admin() {
  log "treetracker-admin-api"
  docker build -t treetracker-admin-api:local "$ROOT/treetracker-admin-api" >/tmp/up-adminapi-build.log 2>&1 \
    || die "admin-api image build failed (see /tmp/up-adminapi-build.log)"
  load_image "treetracker-admin-api:local"
  k apply -k "$ROOT/treetracker-admin-api/deployment/overlays/local" >/dev/null
  k -n admin-api rollout status deploy/treetracker-admin-api --timeout=180s
  seed_admin_user
}

step_admin_client() {
  log "treetracker-admin-client (static build → nginx pod)"
  docker build -t treetracker-admin-client:local -f "$ADMIN_CLIENT/deployment/local/Dockerfile" "$ADMIN_CLIENT" \
    >/tmp/up-adminclient-build.log 2>&1 || die "admin-client image build failed (see /tmp/up-adminclient-build.log)"
  load_image "treetracker-admin-client:local"
  k apply -f "$ADMIN_CLIENT/deployment/local/k8s.yaml" >/dev/null
  k -n admin-client rollout status deploy/treetracker-admin-client --timeout=180s
  info "in-cluster: nginx serves the build + proxies /auth,/api to admin-api (same-origin, no CORS)"
  [ "$ENV" = local ] && expose_admin_client
}

# Persistent host port-forward so the e2e browser (chromedriver on the host) can reach the pod.
# nohup + disown ⇒ it outlives up.sh; down.sh (or a re-run) cleans it up.
expose_admin_client() {
  local code
  code=$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://localhost:$ADMIN_CLIENT_PORT/" 2>/dev/null || true)
  if [ "$code" = 000 ] || [ -z "$code" ]; then
    pkill -f "port-forward svc/treetracker-admin-client" 2>/dev/null || true; sleep 1
    nohup kubectl --context "$CONTEXT" -n admin-client port-forward svc/treetracker-admin-client \
      "$ADMIN_CLIENT_PORT:80" </dev/null >/tmp/up-adminclient-pf.log 2>&1 &
    disown 2>/dev/null || true
    local i; for i in $(seq 1 20); do
      [ "$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://localhost:$ADMIN_CLIENT_PORT/" 2>/dev/null)" = 200 ] && break; sleep 1
    done
  fi
  [ "$(curl -s -o /dev/null -m 2 -w '%{http_code}' "http://localhost:$ADMIN_CLIENT_PORT/" 2>/dev/null)" = 200 ] \
    || die "admin-client not reachable on :$ADMIN_CLIENT_PORT (see /tmp/up-adminclient-pf.log)"
  info "ADMIN_URL=http://localhost:$ADMIN_CLIENT_PORT  (login: ${ADMIN_USER:-test} / ${ADMIN_PASSWORD:-ieVyaGqyMX})"
}

# Seed the legacy admin_user for the /verify login (username/password + HMAC-SHA512(pw,salt)).
seed_admin_user() {
  local user="${ADMIN_USER:-test}" pass="${ADMIN_PASSWORD:-ieVyaGqyMX}" salt hash POD
  salt=$(node -e "console.log(require('crypto').randomBytes(16).toString('hex'))")
  hash=$(node -e "console.log(require('crypto').createHmac('sha512','$salt').update('$pass').digest('hex'))")
  POD=$(k -n data get pod -l app=postgres -o jsonpath='{.items[0].metadata.name}')
  k -n data exec -i "$POD" -- psql -U postgres -d treetracker >/dev/null <<SQL || die "admin user seed failed"
BEGIN;
DELETE FROM admin_user_role WHERE admin_user_id IN (SELECT id FROM admin_user WHERE user_name='$user');
DELETE FROM admin_user WHERE user_name='$user';
DELETE FROM admin_role WHERE role_name='Local Super';
WITH r AS (
  INSERT INTO admin_role (role_name,description,policy,active,created_at)
  VALUES ('Local Super','local e2e super admin',
    '{"policies":[{"name":"super_permission"},{"name":"list_tree"},{"name":"approve_tree"},{"name":"list_user"},{"name":"manager_user"}]}'::json,
    true, now()) RETURNING id
), u AS (
  INSERT INTO admin_user (user_name,password_hash,salt,email,active,enabled,created_at)
  VALUES ('$user','$hash','$salt','$user@greenstand.org', true, true, now()) RETURNING id
)
INSERT INTO admin_user_role (role_id, admin_user_id, active) SELECT r.id, u.id, true FROM r, u;
COMMIT;
SQL
  info "seeded admin user '$user' (super role)"
}

run_all() {
  step_cluster; step_infra_images; step_postgres; step_migrate; step_rabbitmq; step_field_data
  step_transformer_v2; step_processor; step_admin; step_admin_client
  log "done — full capture→verify backend up on $CONTEXT"
}

trap stop_pf EXIT
step_preflight
case "${1:-all}" in
  all) run_all ;;
  cluster|infra_images|postgres|migrate|rabbitmq|field_data|transformer_v2|processor|consumer|keycloak|admin|admin_client) "step_${1}" ;;
  *)   die "unknown step '${1}'. steps: cluster infra_images postgres migrate rabbitmq field_data transformer_v2 processor consumer keycloak admin admin_client (or 'all')" ;;
esac
