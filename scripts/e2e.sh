#!/usr/bin/env bash
set -euo pipefail

echo "=== Greenstand E2e Test Runner ==="

# Ensure stack is up
if ! DOCKER_CONFIG="$(dirname "$0")/../.helm-docker-config" helm status greenstand &>/dev/null; then
  echo "Stack not running. Starting..."
  DOCKER_CONFIG="$(dirname "$0")/../.helm-docker-config" helm dependency update
  DOCKER_CONFIG="$(dirname "$0")/../.helm-docker-config" helm install greenstand . -f values/local.yaml
  echo "Waiting for pods..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/managed-by=Helm \
    --timeout=300s -A 2>/dev/null || true
fi

# Seed LocalStack
bash "$(dirname "$0")/seed-localstack.sh"

# Run tests
# Add test invocation here, e.g.:
# npx jest --testPathPattern=e2e/
# pytest tests/e2e/
echo "No test suite configured yet. Add test commands to scripts/e2e.sh"
echo "Done."
