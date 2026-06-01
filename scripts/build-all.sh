#!/usr/bin/env bash
set -euo pipefail

# Build all Greenstand service images and push them to the local k3d registry.
# Prerequisites: `make setup` must have completed (Colima + k3d running).

REGISTRY="localhost:5000"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Use the real Docker CLI (not the Podman shim) with Colima's socket.
DOCKER_BIN="/opt/homebrew/opt/docker/bin/docker"
if [ ! -x "$DOCKER_BIN" ]; then
  echo "ERROR: Docker CLI not found at $DOCKER_BIN. Run: brew install docker"
  exit 1
fi

export DOCKER_HOST="unix://$HOME/.colima/default/docker.sock"
export DOCKER_CONFIG="$REPO_ROOT/.helm-docker-config"
# BuildKit's docker-container driver negotiates an API version Colima's daemon rejects.
export DOCKER_BUILDKIT=0
mkdir -p "$DOCKER_CONFIG"

# Services: "dir_name:registry_image_name"
SERVICES=(
  "bulk-pack-consumer:bulk-pack-consumer"
  "bulk-pack-processor:bulk-pack-processor"
  "bulk-pack-transformer:bulk-pack-transformer"
  "images-api:images-api"
  "map-config-api:map-config-api"
  "treetracker-admin-api:treetracker-admin-api"
  "treetracker-api:treetracker-api"
  "treetracker-auth:treetracker-auth"
  "treetracker-contract-api:treetracker-contract-api"
  "treetracker-denormalization:treetracker-denormalization"
  "treetracker-earnings-api:treetracker-earnings-api"
  "treetracker-field-data:treetracker-field-data"
  "treetracker-grower-account-query:treetracker-grower-account-query"
  "treetracker-like:treetracker-like"
  "treetracker-map-tile-server:treetracker-map-tile-server"
  "treetracker-messaging-api:treetracker-messaging-api"
  "treetracker-query-api:treetracker-query-api"
  "treetracker-regions-api:treetracker-regions-api"
  "treetracker-reporting:treetracker-reporting"
  "treetracker-stakeholder-api:treetracker-stakeholder-api"
  "treetracker-wallet-api:treetracker-wallet-api"
  "treetracker-web-map-api:treetracker-web-map-api"
  "treetracker-web-map-client:treetracker-web-map-client"
  "webmap-query-service-consumer:webmap-query-service-consumer"
)

SKIPPED=()
BUILT=()
FAILED=()

# Patch a Dockerfile into a temp dir, replacing npm ci with --legacy-peer-deps and
# injecting any extra setup needed. Returns the patched Dockerfile path.
# Caller must rm the returned directory.
patch_dockerfile() {
  local svc_dir="$1"
  local svc_path="$REPO_ROOT/services/$svc_dir"
  local tmpdir
  tmpdir=$(mktemp -d)

  local npm_cmd="npm ci --legacy-peer-deps"
  local extra_setup=""

  case "$svc_dir" in
    bulk-pack-transformer)
      # bcrypt requires native compilation (Python, make, g++) on Alpine
      extra_setup="apk add --no-cache python3 make g++ git && "
      ;;
    treetracker-map-tile-server)
      # A dependency is installed from a GitHub URL; needs git in the image
      extra_setup="apk add --no-cache git && "
      ;;
    webmap-query-service-consumer)
      # package-lock.json is out of sync; use npm install instead of npm ci
      npm_cmd="npm install --legacy-peer-deps"
      ;;
  esac

  sed "s|npm ci --silent|${extra_setup}${npm_cmd}|g
       s|^RUN npm ci$|RUN ${extra_setup}${npm_cmd}|
       s|npm ci --production|${extra_setup}${npm_cmd} --production|g" \
    "$svc_path/Dockerfile" > "$tmpdir/Dockerfile"

  echo "$tmpdir"
}

# For services whose Dockerfiles expect pre-built artifacts (dist/, node_modules/) on
# the host, produce those artifacts inside a throwaway container first.
pre_build() {
  local svc_dir="$1"
  local svc_path="$REPO_ROOT/services/$svc_dir"

  case "$svc_dir" in
    treetracker-query-api)
      # Dockerfile COPYs dist/ — TypeScript must be compiled first
      if [ ! -d "$svc_path/dist" ]; then
        local node_img
        node_img=$(grep '^FROM' "$svc_path/Dockerfile" | head -1 | awk '{print $2}')
        echo "    pre-build: compiling TypeScript in $node_img"
        "$DOCKER_BIN" run --rm \
          -v "$svc_path:/work" -w /work "$node_img" \
          sh -c "npm ci --legacy-peer-deps && npm run build" 2>&1 | tail -3
      fi
      ;;
    webmap-query-service-consumer)
      # Dockerfile COPYs node_modules/ and dist/ — both must exist on host
      if [ ! -d "$svc_path/node_modules" ]; then
        local node_img
        node_img=$(grep '^FROM' "$svc_path/Dockerfile" | head -1 | awk '{print $2}')
        echo "    pre-build: npm install + build in $node_img"
        "$DOCKER_BIN" run --rm \
          -v "$svc_path:/work" -w /work "$node_img" \
          sh -c "npm install --legacy-peer-deps && npm run build" 2>&1 | tail -3
      fi
      ;;
  esac
}

for entry in "${SERVICES[@]}"; do
  svc_dir="${entry%%:*}"
  img_name="${entry##*:}"
  svc_path="$REPO_ROOT/services/$svc_dir"
  tag="$REGISTRY/$img_name:latest"

  if [ ! -f "$svc_path/Dockerfile" ]; then
    SKIPPED+=("$svc_dir (no Dockerfile)")
    continue
  fi

  # treetracker-like: Dockerfile references apps/like/prisma/schema.prisma which
  # doesn't exist in the checked-out submodule (Prisma schema was likely moved).
  if [ "$svc_dir" = "treetracker-like" ]; then
    SKIPPED+=("treetracker-like (Dockerfile references missing apps/like/prisma/schema.prisma)")
    continue
  fi

  # treetracker-map-tile-server: depends on a GitHub-URL npm package (Windshaft) that
  # requires git within the Docker build context; the submodule .git pointer breaks
  # git's repo-discovery inside Docker. Skipping until resolved upstream.
  if [ "$svc_dir" = "treetracker-map-tile-server" ]; then
    SKIPPED+=("treetracker-map-tile-server (npm dep uses GitHub URL; git fails in Docker build context)")
    continue
  fi

  echo ""
  echo "==> $svc_dir → $tag"

  pre_build "$svc_dir"

  tmpdir=$(patch_dockerfile "$svc_dir")
  if "$DOCKER_BIN" build -f "$tmpdir/Dockerfile" -t "$tag" "$svc_path" \
     && "$DOCKER_BIN" push "$tag"; then
    BUILT+=("$img_name")
  else
    FAILED+=("$svc_dir")
    echo "    FAILED: $svc_dir"
  fi
  rm -rf "$tmpdir"
done

echo ""
echo "================================================"
echo "Built (${#BUILT[@]}): ${BUILT[*]:-none}"
echo ""
if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo "Skipped (${#SKIPPED[@]}):"
  for s in "${SKIPPED[@]}"; do echo "  - $s"; done
fi
if [ ${#FAILED[@]} -gt 0 ]; then
  echo ""
  echo "Failed (${#FAILED[@]}):"
  for f in "${FAILED[@]}"; do echo "  - $f"; done
  exit 1
fi
echo ""
echo "Run 'make upgrade' to redeploy with local images."
