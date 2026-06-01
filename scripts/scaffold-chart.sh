#!/usr/bin/env bash
set -euo pipefail

NAME=${1:?Usage: scaffold-chart.sh <name> <image-repo> <port>}
IMAGE=${2:?Usage: scaffold-chart.sh <name> <image-repo> <port>}
PORT=${3:?Usage: scaffold-chart.sh <name> <image-repo> <port>}

CHART_DIR="charts/$NAME"

if [ -d "$CHART_DIR" ]; then
  echo "Chart already exists at $CHART_DIR — skipping."
  exit 0
fi

mkdir -p "$CHART_DIR/templates"

cat > "$CHART_DIR/Chart.yaml" << EOF
apiVersion: v2
name: $NAME
description: Greenstand $NAME
type: application
version: 0.1.0
appVersion: "latest"
EOF

cat > "$CHART_DIR/values.yaml" << EOF
replicaCount: 2

image:
  repository: $IMAGE
  tag: latest
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: $PORT

env: []
# env:
#   - name: DATABASE_URL
#     value: "postgresql://user:pass@postgres:5432/treetracker"

resources: {}
EOF

cp charts/_base/templates/_helpers.tpl "$CHART_DIR/templates/"
cp charts/_base/templates/deployment.yaml "$CHART_DIR/templates/"
cp charts/_base/templates/service.yaml "$CHART_DIR/templates/"

echo "Created chart at $CHART_DIR"
