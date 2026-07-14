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
step_transformer_v2() { info "TODO: bulk-pack-transformer-v2 (:3006, TREETRACKER_FIELD_DATA_URL→field-data svc)"; }
step_processor()      { info "TODO: bulk-pack-processor CronJob (reads data_pipeline.bulk_tree_upload)"; }
step_consumer()       { info "TODO: treetracker-data-pipeline consumer (SQS treetracker-local-queue→bulk_tree_upload; needs Dockerfile)"; }
step_keycloak()       { info "TODO: Keycloak (keycloak DB, realm treetracker, admin user)"; }
step_admin()          { info "TODO: admin-api + admin-client (/verify), resolve admin auth"; }

run_all() {
  step_cluster; step_infra_images; step_postgres; step_migrate; step_rabbitmq; step_field_data
  step_transformer_v2; step_processor; step_consumer; step_keycloak; step_admin
  log "done — data layer + field-data up on $CONTEXT"
}

trap stop_pf EXIT
step_preflight
case "${1:-all}" in
  all) run_all ;;
  cluster|infra_images|postgres|migrate|rabbitmq|field_data|transformer_v2|processor|consumer|keycloak|admin) "step_${1}" ;;
  *)   die "unknown step '${1}'. steps: cluster infra_images postgres migrate rabbitmq field_data transformer_v2 processor consumer keycloak admin (or 'all')" ;;
esac
