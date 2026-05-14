#!/usr/bin/env bash
set -euo pipefail

# Setup for macOS using k3d (k3s in Podman containers)

# Ensure Podman machine is running and export its socket as DOCKER_HOST
if command -v podman &>/dev/null; then
  PODMAN_SOCK=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)
  if [ -n "$PODMAN_SOCK" ] && [ -S "$PODMAN_SOCK" ]; then
    export DOCKER_HOST="unix://$PODMAN_SOCK"
    echo "Using Podman socket: $DOCKER_HOST"
  else
    echo "Starting Podman machine..."
    podman machine start 2>/dev/null || true
    PODMAN_SOCK=$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null || true)
    [ -n "$PODMAN_SOCK" ] && export DOCKER_HOST="unix://$PODMAN_SOCK"
  fi
fi

# Install k3d if not present
if ! command -v k3d &>/dev/null; then
  echo "Installing k3d..."
  brew install k3d
fi

# Create cluster with a built-in registry at localhost:5000
# --registry-create creates a registry container and configures k3s to trust it
if k3d cluster list 2>/dev/null | grep -q '^greenstand'; then
  echo "Cluster 'greenstand' already exists — skipping creation."
else
  echo "Creating k3d cluster with local registry..."
  k3d cluster create greenstand \
    --registry-create greenstand-registry:0.0.0.0:5000 \
    --wait
fi

# Merge kubeconfig so kubectl/helm work without extra flags
k3d kubeconfig merge greenstand --kubeconfig-merge-default
echo "Kubeconfig updated. Current context: $(kubectl config current-context)"

echo ""
echo "k3d cluster is ready. Next steps:"
echo "  make submodules   # pull all service repos"
echo "  make up           # deploy the full stack"
