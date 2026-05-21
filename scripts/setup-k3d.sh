#!/usr/bin/env bash
set -euo pipefail

# Setup for macOS using k3d (k3s in Podman containers)

# Ensure Podman machine is running in rootful mode and export its socket as DOCKER_HOST.
# k3d uses the Docker API with --network=bridge; Podman's Docker compat layer only
# exposes a 'bridge' network in rootful mode (rootless uses 'podman' as the default).
if command -v podman &>/dev/null; then
  ROOTFUL=$(podman machine inspect --format '{{.Rootful}}' 2>/dev/null || echo "false")
  if [ "$ROOTFUL" != "true" ]; then
    echo "Switching Podman to rootful mode (required for k3d bridge-network compatibility)..."
    podman machine stop 2>/dev/null || true
    podman machine set --rootful
    podman machine start
  else
    PODMAN_SOCK=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)
    if [ -z "$PODMAN_SOCK" ] || [ ! -S "$PODMAN_SOCK" ]; then
      echo "Starting Podman machine..."
      podman machine start
    fi
  fi
  PODMAN_SOCK=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)
  [ -n "$PODMAN_SOCK" ] && export DOCKER_HOST="unix://$PODMAN_SOCK"
  echo "Using Podman socket: $DOCKER_HOST"
fi

# Preflight: port 5000 must be free for the local registry.
# On macOS, Control Center's AirPlay Receiver occupies this port by default.
if lsof -nP -i :5000 -sTCP:LISTEN 2>/dev/null | grep -v 'k3d\|podman\|registry\|gvproxy\|^COMMAND' | grep -q .; then
  echo ""
  echo "ERROR: Port 5000 is already in use (usually macOS AirPlay Receiver)."
  echo "Disable it with:"
  echo "  sudo defaults write /Library/Preferences/com.apple.controlcenter.plist AirplayRecieverEnabled -bool false && killall ControlCenter"
  echo ""
  exit 1
fi

# Install k3d if not present
if ! command -v k3d &>/dev/null; then
  echo "Installing k3d..."
  brew install k3d
fi

# Clean up any orphaned registry container left by a previous failed run.
# k3d registry list only shows running registries, so a 'Created'-state container
# won't appear there but will still block port 5000 on start.
if podman container exists k3d-greenstand-registry 2>/dev/null && \
   ! k3d registry list 2>/dev/null | grep -q 'greenstand-registry'; then
  echo "Removing orphaned registry container from previous failed run..."
  podman rm -f k3d-greenstand-registry 2>/dev/null || true
fi

# Create the registry separately so we can override --default-network.
# k3d's --registry-create (and registry create) default to --default-network=bridge,
# which Podman does not expose as a named network; 'podman' is the correct default.
if k3d registry list 2>/dev/null | grep -q 'greenstand-registry'; then
  echo "Registry 'greenstand-registry' already exists — skipping."
else
  echo "Creating local registry at localhost:5000..."
  k3d registry create greenstand-registry --port 5000 --default-network podman
fi

# Create cluster referencing the pre-existing registry
if k3d cluster list 2>/dev/null | grep -q '^greenstand'; then
  echo "Cluster 'greenstand' already exists — skipping creation."
else
  echo "Creating k3d cluster..."
  k3d cluster create greenstand \
    --registry-use k3d-greenstand-registry:5000 \
    --wait
fi

# Merge kubeconfig so kubectl/helm work without extra flags
k3d kubeconfig merge greenstand --kubeconfig-merge-default
echo "Kubeconfig updated. Current context: $(kubectl config current-context)"

echo ""
echo "k3d cluster is ready. Next steps:"
echo "  make submodules   # pull all service repos"
echo "  make up           # deploy the full stack"
