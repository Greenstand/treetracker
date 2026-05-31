#!/usr/bin/env bash
set -euo pipefail

# Setup for macOS using k3d with Colima (Docker-compatible runtime)

# Ensure the real Docker CLI (from Homebrew) is used instead of any Podman shim.
# Colima's provisioning runs `docker context create` which requires the real Docker client.
export PATH="/opt/homebrew/bin:$PATH"

# Ensure Colima is running
if ! colima status 2>/dev/null | grep -q "Running"; then
  echo "Starting Colima..."
  # --activate=false skips Docker context registration on the host, which fails when
  # the `docker` CLI is a Podman shim. We set DOCKER_HOST directly instead.
  colima start --runtime docker --activate=false
fi

COLIMA_SOCK="$HOME/.colima/default/docker.sock"
if [ ! -S "$COLIMA_SOCK" ]; then
  echo "ERROR: Colima Docker socket not found at $COLIMA_SOCK"
  echo "Try: colima start --runtime docker"
  exit 1
fi
export DOCKER_HOST="unix://$COLIMA_SOCK"
echo "Using Colima socket: $DOCKER_HOST"

# Preflight: port 5000 must be free for the local registry.
# On macOS, Control Center's AirPlay Receiver occupies this port by default.
if lsof -nP -i :5000 -sTCP:LISTEN 2>/dev/null | grep -v 'k3d\|colima\|registry\|^COMMAND' | grep -q .; then
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

# Clean up any orphaned registry container left by a previous failed run
if docker inspect k3d-greenstand-registry &>/dev/null 2>&1 && \
   ! k3d registry list 2>/dev/null | grep -q 'greenstand-registry'; then
  echo "Removing orphaned registry container from previous failed run..."
  docker rm -f k3d-greenstand-registry 2>/dev/null || true
fi

# Create the registry
if k3d registry list 2>/dev/null | grep -q 'greenstand-registry'; then
  echo "Registry 'greenstand-registry' already exists — skipping."
else
  echo "Creating local registry at localhost:5000..."
  k3d registry create greenstand-registry --port 5000
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
