#!/usr/bin/env bash
# Replace large disabled-locally Helm dependency charts with minimal stub tarballs.
#
# Helm bundles ALL dependency chart tarballs into the Helm release Secret,
# regardless of 'enabled: false' conditions. Disabled charts that are large
# (airflow, cert-manager, keycloak, sealed-secrets) push the Secret over
# Kubernetes's 3MB request-body limit. This script overwrites those tarballs
# with stubs that contain only Chart.yaml, keeping the Secret small.
#
# Run this AFTER 'helm dependency update' and BEFORE 'helm install/upgrade'.
# 'helm dependency update' will restore the real tarballs on the next run.

set -euo pipefail

# emissary-ingress (ambassador) is amd64-only and crashes on Apple Silicon
DISABLED_CHARTS="airflow cert-manager keycloak sealed-secrets emissary-ingress"

for name in $DISABLED_CHARTS; do
  tarball=$(ls "charts/$name"-*.tgz 2>/dev/null | head -1 || true)
  [ -z "$tarball" ] && continue

  version=$(basename "$tarball" .tgz | sed "s/^${name}-//")
  tmpdir=$(mktemp -d)
  mkdir -p "$tmpdir/$name"
  printf 'apiVersion: v2\nname: %s\nversion: %s\n' "$name" "$version" \
    > "$tmpdir/$name/Chart.yaml"
  tar czf "$tarball" -C "$tmpdir" "$name"
  rm -rf "$tmpdir"
  echo "Stubbed: $tarball"
done
