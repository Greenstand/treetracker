#!/usr/bin/env bash
set -euo pipefail

# Install k3s (lightweight Kubernetes) if not present
if ! command -v k3s &>/dev/null; then
  echo "Installing k3s..."
  curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -
fi

# Start a local Docker registry on port 5000 if not already running
if ! docker ps --format '{{.Names}}' | grep -q '^local-registry$'; then
  echo "Starting local registry..."
  docker run -d -p 5000:5000 --restart=always --name local-registry registry:2
fi

# Configure k3s to trust the local registry
sudo mkdir -p /etc/rancher/k3s
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null << 'REGISTRY'
mirrors:
  "localhost:5000":
    endpoint:
      - "http://localhost:5000"
REGISTRY

# Restart k3s to pick up registry config
sudo systemctl restart k3s
echo "Waiting for k3s to be ready..."
sudo k3s kubectl wait --for=condition=ready node --all --timeout=60s

# Copy kubeconfig so helm/kubectl work without sudo
mkdir -p ~/.kube
sudo k3s kubectl config view --raw | \
  sed 's|https://127.0.0.1:6443|https://127.0.0.1:6443|' \
  > ~/.kube/config
chmod 600 ~/.kube/config

echo "k3s is ready. Run: make up"
