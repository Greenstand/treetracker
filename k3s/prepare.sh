#!/usr/bin/env bash
#
# prepare.sh — LOCAL MACHINE bootstrap (macOS-specific). Run once (and again if your LAN IP changes).
# Installs the host tools and fixes Docker's proxy so image pulls work behind ClashX.
# Everything here is specific to THIS machine; the portable stack setup lives in up.sh.
#
# Usage: ./k3s/prepare.sh
#
set -euo pipefail

PROXY_PORT="${PROXY_PORT:-7890}"          # ClashX local port
c_grn=$'\033[32m'; c_red=$'\033[31m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
log()  { echo "${c_grn}▶${c_off} $*"; }
info() { echo "${c_dim}  $*${c_off}"; }
warn() { echo "${c_yel}! $*${c_off}"; }
die()  { echo "${c_red}✖ $*${c_off}" >&2; exit 1; }

export PATH="/opt/homebrew/bin:$PATH"

# ── 1. Host tools (Homebrew) ────────────────────────────────────────────────
log "host tools"
command -v brew >/dev/null 2>&1 || die "Homebrew not installed — https://brew.sh"
for f in k3d helm awscli libpq; do
  brew list "$f" >/dev/null 2>&1 || { info "brew install $f"; brew install "$f"; }
done
# libpq is keg-only → link psql/pg_dump onto PATH
command -v psql >/dev/null 2>&1 || brew link --force libpq >/dev/null 2>&1 || true
command -v psql >/dev/null 2>&1 || warn "psql still not on PATH — add \$(brew --prefix libpq)/bin to your PATH"
# node (via nvm) is needed by up.sh for db-migrate
if ! command -v node >/dev/null 2>&1 && ! ls "$HOME"/.nvm/versions/node/*/bin/node >/dev/null 2>&1; then
  warn "node not found — install Node (e.g. via nvm); up.sh needs it for db-migrate"
fi

# ── 2. Docker Desktop ────────────────────────────────────────────────────────
log "docker desktop"
[ -d /Applications/Docker.app ] || command -v docker >/dev/null 2>&1 || die "Docker Desktop not installed"
if ! docker info >/dev/null 2>&1; then
  info "starting Docker Desktop…"; open -a Docker
  for i in $(seq 1 150); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || die "Docker daemon did not start"
fi

# ── 3. ClashX must allow LAN (so Docker's VM can reach the host proxy) ────────
log "proxy (ClashX)"
if lsof -nP -iTCP:"$PROXY_PORT" -sTCP:LISTEN 2>/dev/null | grep -q "127.0.0.1:$PROXY_PORT"; then
  warn "ClashX is bound to 127.0.0.1 only — enable 'Allow connections from LAN' in ClashX, then re-run."
fi

# ── 4. Point Docker's daemon proxy at the current LAN IP (fixes image pulls) ──
if ! docker pull hello-world >/dev/null 2>&1; then
  log "fixing Docker proxy (pull currently failing)"
  ip="$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')" 2>/dev/null)"
  [ -n "$ip" ] || die "no LAN IP found"
  settings="$HOME/Library/Group Containers/group.com.docker/settings-store.json"
  osascript -e 'quit app "Docker"' 2>/dev/null || true; sleep 3
  python3 - "$settings" "$ip" "$PROXY_PORT" <<'PY'
import json,sys
p,ip,port=sys.argv[1],sys.argv[2],sys.argv[3]
d=json.load(open(p))
d['ProxyHTTPMode']='manual'
d['OverrideProxyHTTP']=f'http://{ip}:{port}'
d['OverrideProxyHTTPS']=f'http://{ip}:{port}'
d['OverrideProxyExcludes']='localhost,127.0.0.1,.svc,.cluster.local,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16'
json.dump(d,open(p,'w'),indent=2)
PY
  info "docker proxy → http://$ip:$PROXY_PORT ; restarting Docker…"
  open -a Docker
  for i in $(seq 1 150); do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker pull hello-world >/dev/null 2>&1 || die "docker pull still failing (is ClashX 'Allow LAN' on?)"
fi
docker rmi hello-world >/dev/null 2>&1 || true

log "prepare complete — now run: ./k3s/up.sh"
