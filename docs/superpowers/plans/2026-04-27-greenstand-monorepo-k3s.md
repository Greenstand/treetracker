# Greenstand Monorepo + k3s Local Deployment — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a monorepo with git submodules and an umbrella Helm chart that deploys the full Greenstand service stack into a local k3s cluster for e2e testing and local development, with Skaffold for per-service image builds.

**Architecture:** An umbrella `Chart.yaml` at the repo root declares every Greenstand service as a Helm dependency — either pointing to a chart inside its git submodule (`file://services/<name>/charts/<name>`) or to a locally maintained chart under `charts/<name>/`. Infrastructure services (postgres, localstack, ambassador, keycloak, airflow) use upstream Helm repos. `values/local.yaml` sets replicas to 1, uses a single Postgres instance, and redirects all AWS SDK calls to LocalStack. Skaffold profiles allow any single service to be rebuilt from source and hot-swapped without restarting the rest of the stack.

**Tech Stack:** k3s v1.29+, Helm 3.14+, Skaffold v2.10+, Docker, LocalStack 3.x, bitnami/postgresql, Apache Airflow 2.x (LocalExecutor), Emissary-Ingress (Ambassador successor)

---

## File Map

| File | Purpose |
|---|---|
| `Chart.yaml` | Umbrella chart — all service and infra dependencies |
| `values.yaml` | Defaults: published images, 2 replicas, real AWS endpoints |
| `values/local.yaml` | Local overrides: 1 replica, single postgres, localstack endpoints |
| `values/staging.yaml` | Staging overrides (placeholder) |
| `charts/_base/templates/_helpers.tpl` | Generic Helm helpers shared across all scaffolded charts |
| `charts/_base/templates/deployment.yaml` | Generic Deployment template |
| `charts/_base/templates/service.yaml` | Generic Service template |
| `charts/<service>/Chart.yaml` | Per-service chart metadata |
| `charts/<service>/values.yaml` | Per-service defaults (image repo, port, env vars) |
| `charts/<service>/templates/` | Copied from `charts/_base/templates/` |
| `charts/postgrest/` | PostgREST chart (no upstream Helm chart exists) |
| `skaffold.yaml` | Skaffold profiles — one per service |
| `Makefile` | Thin aliases for helm, skaffold, k3s commands |
| `scripts/setup-k3s.sh` | One-time k3s install + local registry configuration |
| `scripts/scaffold-chart.sh` | Generates a new service chart from `charts/_base` |
| `scripts/seed-localstack.sh` | Creates S3 buckets and SQS queues in LocalStack |
| `README.md` | Updated usage instructions |

---

## Task 1: Makefile + k3s Setup Script

**Files:**
- Create: `Makefile`
- Create: `scripts/setup-k3s.sh`

- [ ] **Step 1: Create scripts directory**

```bash
mkdir -p scripts
```

- [ ] **Step 2: Create `scripts/setup-k3s.sh`**

```bash
cat > scripts/setup-k3s.sh << 'SCRIPT'
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
SCRIPT
chmod +x scripts/setup-k3s.sh
```

- [ ] **Step 3: Create `Makefile`**

```makefile
cat > Makefile << 'EOF'
.PHONY: setup up upgrade down dev e2e submodules lint

setup:
	bash scripts/setup-k3s.sh

submodules:
	git submodule update --init --recursive

up:
	helm dependency update
	helm install greenstand . -f values/local.yaml

upgrade:
	helm dependency update
	helm upgrade greenstand . -f values/local.yaml

down:
	helm uninstall greenstand

dev:
	@if [ -z "$(SERVICE)" ]; then echo "Usage: make dev SERVICE=<service-name>"; exit 1; fi
	skaffold dev --profile=$(SERVICE)

e2e:
	bash scripts/e2e.sh

lint:
	helm lint . -f values/local.yaml
	helm template greenstand . -f values/local.yaml > /dev/null
EOF
```

- [ ] **Step 4: Verify Makefile parses correctly**

```bash
make --dry-run up 2>&1 | head -5
```
Expected: should print the `helm` command without running it (no "missing separator" errors).

- [ ] **Step 5: Commit**

```bash
git add Makefile scripts/setup-k3s.sh
git commit -m "feat: add Makefile and k3s setup script"
```

---

## Task 2: Generic Chart Base Templates + Scaffold Script

These templates are identical across all service charts. The scaffold script copies them into each new chart.

**Files:**
- Create: `charts/_base/templates/_helpers.tpl`
- Create: `charts/_base/templates/deployment.yaml`
- Create: `charts/_base/templates/service.yaml`
- Create: `scripts/scaffold-chart.sh`

- [ ] **Step 1: Create base templates directory**

```bash
mkdir -p charts/_base/templates
```

- [ ] **Step 2: Create `charts/_base/templates/_helpers.tpl`**

```bash
cat > charts/_base/templates/_helpers.tpl << 'EOF'
{{- define "service.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "service.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | trunc 63 }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "service.selectorLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
EOF
```

- [ ] **Step 3: Create `charts/_base/templates/deployment.yaml`**

```bash
cat > charts/_base/templates/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "service.fullname" . }}
  labels:
    {{- include "service.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "service.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "service.selectorLabels" . | nindent 8 }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
              protocol: TCP
          {{- if .Values.env }}
          env:
            {{- toYaml .Values.env | nindent 12 }}
          {{- end }}
          {{- if .Values.resources }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          {{- end }}
EOF
```

- [ ] **Step 4: Create `charts/_base/templates/service.yaml`**

```bash
cat > charts/_base/templates/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ include "service.fullname" . }}
  labels:
    {{- include "service.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
      name: http
  selector:
    {{- include "service.selectorLabels" . | nindent 4 }}
EOF
```

- [ ] **Step 5: Create `scripts/scaffold-chart.sh`**

Usage: `bash scripts/scaffold-chart.sh <chart-name> <image-repository> <container-port>`

```bash
cat > scripts/scaffold-chart.sh << 'SCRIPT'
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
SCRIPT
chmod +x scripts/scaffold-chart.sh
```

- [ ] **Step 6: Verify scaffold script works**

```bash
bash scripts/scaffold-chart.sh test-service greenstand/test-service 3000
helm lint charts/test-service/
```
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 7: Remove the test chart**

```bash
rm -rf charts/test-service
```

- [ ] **Step 8: Commit**

```bash
git add charts/_base/ scripts/scaffold-chart.sh
git commit -m "feat: add generic chart base templates and scaffold script"
```

---

## Task 3: Umbrella Chart Skeleton + Infrastructure Dependencies

**Files:**
- Create: `Chart.yaml`
- Create: `values.yaml`
- Create: `values/local.yaml`
- Create: `values/staging.yaml`

- [ ] **Step 1: Add Helm repos for infrastructure charts**

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add localstack https://helm.localstack.cloud
helm repo add apache-airflow https://airflow.apache.org
helm repo add jetstack https://charts.jetstack.io
helm repo add emissary https://app.getambassador.io
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm repo update
```

- [ ] **Step 2: Find latest stable chart versions**

```bash
helm search repo bitnami/postgresql --versions | head -3
helm search repo localstack/localstack --versions | head -3
helm search repo apache-airflow/airflow --versions | head -3
helm search repo jetstack/cert-manager --versions | head -3
helm search repo emissary/emissary-ingress --versions | head -3
helm search repo bitnami/keycloak --versions | head -3
helm search repo sealed-secrets/sealed-secrets --versions | head -3
```

Record the latest version of each chart. Use those versions in the next step.

- [ ] **Step 3: Create `Chart.yaml`** (infra dependencies only — service dependencies added in Task 13)

Replace `<VERSION>` with the versions found in Step 2.

```yaml
# Chart.yaml
apiVersion: v2
name: greenstand
description: Greenstand platform umbrella chart
type: application
version: 0.1.0

dependencies:
  # Infrastructure
  - name: postgresql
    version: "<VERSION>"
    repository: https://charts.bitnami.com/bitnami
    alias: postgres
    condition: postgres.enabled

  - name: localstack
    version: "<VERSION>"
    repository: https://helm.localstack.cloud
    condition: localstack.enabled

  - name: airflow
    version: "<VERSION>"
    repository: https://airflow.apache.org
    condition: airflow.enabled

  - name: cert-manager
    version: "<VERSION>"
    repository: https://charts.jetstack.io
    condition: cert-manager.enabled

  - name: emissary-ingress
    version: "<VERSION>"
    repository: https://app.getambassador.io
    alias: ambassador
    condition: ambassador.enabled

  - name: keycloak
    version: "<VERSION>"
    repository: https://charts.bitnami.com/bitnami
    condition: keycloak.enabled

  - name: sealed-secrets
    version: "<VERSION>"
    repository: https://bitnami-labs.github.io/sealed-secrets
    condition: sealed-secrets.enabled
```

- [ ] **Step 4: Create `values.yaml`** (infrastructure defaults only — service defaults added in Task 14)

```yaml
# values.yaml
postgres:
  enabled: true
  auth:
    database: treetracker
    username: treetracker
    password: treetracker
  primary:
    persistence:
      enabled: true
      size: 10Gi

localstack:
  enabled: false  # only enabled locally

airflow:
  enabled: true
  executor: LocalExecutor
  webserverSecretKey: "a-random-secret-key-change-me"
  redis:
    enabled: false
  workers:
    replicas: 0
  flower:
    enabled: false
  dags:
    persistence:
      enabled: false
    gitSync:
      enabled: false

cert-manager:
  enabled: true
  installCRDs: true

ambassador:
  enabled: true

keycloak:
  enabled: true
  auth:
    adminUser: admin
    adminPassword: admin

sealed-secrets:
  enabled: true
```

- [ ] **Step 5: Create `values/local.yaml`**

```yaml
# values/local.yaml — local k3s overrides

# --- Infrastructure ---
postgres:
  primary:
    persistence:
      size: 2Gi
  readReplicas:
    replicaCount: 0

localstack:
  enabled: true
  startServices: "s3,sqs,sns"

airflow:
  executor: LocalExecutor
  workers:
    replicas: 0

# S3/SQS/SNS → LocalStack for all services
aws:
  endpoint: "http://greenstand-localstack:4566"
  region: us-east-1
  accessKeyId: test
  secretAccessKey: test

# --- Per-service replica overrides (1 replica locally) ---
# Populated in Task 14 after all service charts are added.
```

- [ ] **Step 6: Create `values/staging.yaml`**

```yaml
# values/staging.yaml — staging-specific overrides
# Add staging values here as needed.
```

- [ ] **Step 7: Create `mkdir -p values`**

```bash
mkdir -p values
```

- [ ] **Step 8: Run `helm dependency update` to validate Chart.yaml**

```bash
helm dependency update
```
Expected: Downloads infra charts to `charts/` and generates `Chart.lock`. No errors.

- [ ] **Step 9: Lint the skeleton**

```bash
helm lint . -f values/local.yaml
```
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 10: Commit**

```bash
git add Chart.yaml values.yaml values/local.yaml values/staging.yaml
git commit -m "feat: add umbrella chart skeleton with infrastructure dependencies"
```

---

## Task 4: Add Git Submodules for All Services

Add every service as a submodule under `services/`. If any repo name is wrong, browse https://github.com/Greenstand to find the correct name.

**Files:**
- Modify: `.gitmodules` (auto-updated by git submodule add)

- [ ] **Step 1: Add auth + core API submodules**

```bash
git submodule add https://github.com/Greenstand/treetracker-auth services/treetracker-auth
git submodule add https://github.com/Greenstand/treetracker-admin-api services/treetracker-admin-api
git submodule add https://github.com/Greenstand/treetracker-field-data services/treetracker-field-data
git submodule add https://github.com/Greenstand/treetracker-wallet-api services/treetracker-wallet-api
git submodule add https://github.com/Greenstand/treetracker-messaging-api services/treetracker-messaging-api
git submodule add https://github.com/Greenstand/treetracker-stakeholder-api services/treetracker-stakeholder-api
git submodule add https://github.com/Greenstand/treetracker-reporting services/treetracker-reporting
git submodule add https://github.com/Greenstand/treetracker-like services/treetracker-like
git submodule add https://github.com/Greenstand/treetracker-api services/treetracker-api
```

- [ ] **Step 2: Add data + pipeline submodules**

```bash
git submodule add https://github.com/Greenstand/treetracker-grower-account-query services/treetracker-grower-account-query
git submodule add https://github.com/Greenstand/images-api services/images-api
git submodule add https://github.com/Greenstand/treetracker-map-tile-server services/treetracker-map-tile-server
git submodule add https://github.com/Greenstand/treetracker-denormalization services/treetracker-denormalization
git submodule add https://github.com/Greenstand/bulk-pack-consumer services/bulk-pack-consumer
git submodule add https://github.com/Greenstand/bulk-pack-transformer services/bulk-pack-transformer
git submodule add https://github.com/Greenstand/bulk-pack-processor services/bulk-pack-processor
git submodule add https://github.com/Greenstand/webmap-query-service-consumer services/webmap-query-service-consumer
```

- [ ] **Step 3: Add webmap + config + gateway submodules**

```bash
git submodule add https://github.com/Greenstand/treetracker-query-api services/treetracker-query-api
git submodule add https://github.com/Greenstand/map-config-api services/map-config-api
git submodule add https://github.com/Greenstand/treetracker-gateway services/treetracker-gateway
```

Note: If `treetracker-gateway` is not the correct repo name, check https://github.com/Greenstand for the gateway service repo.

- [ ] **Step 4: Add client submodules**

```bash
git submodule add https://github.com/Greenstand/treetracker-admin-client services/treetracker-admin-client
git submodule add https://github.com/Greenstand/treetracker-wallet-app services/treetracker-wallet-app
git submodule add https://github.com/Greenstand/treetracker-web-map-client services/treetracker-web-map-client
```

- [ ] **Step 5: Add wallet monorepo submodule**

```bash
git submodule add https://github.com/Greenstand/treetracker-wallet services/treetracker-wallet
```

- [ ] **Step 6: Verify submodules**

```bash
git submodule status
```
Expected: All submodules listed with their current commit hash (no `-` prefix errors).

- [ ] **Step 7: Commit**

```bash
git add .gitmodules services/
git commit -m "feat: add git submodules for all Greenstand services"
```

---

## Task 5: Audit Submodules for Existing Helm Charts

Before scaffolding charts, check which service repos already have Helm charts — those can be referenced directly.

**Files:** None created — this is an audit step that informs Tasks 6–10.

- [ ] **Step 1: Find existing Helm charts in submodules**

```bash
find services/ -name "Chart.yaml" | sort
```

For each result, note whether the chart is production-ready (has a `templates/deployment.yaml`) or just a stub.

- [ ] **Step 2: Check the treetracker-infrastructure repo for existing manifests**

The existing infrastructure configuration may be at https://github.com/Greenstand/treetracker-infrastructure or https://github.com/Greenstand/argo-cd. Browse those repos to find Helm charts or k8s manifests that can be adapted.

- [ ] **Step 3: Record which services need new charts**

For each service WITHOUT a usable existing chart, scaffold one in Tasks 6–10. For each service WITH an existing chart, note the path — it will be used in Task 13 as `file://services/<service>/charts/<chart-name>`.

---

## Task 6: Scaffold Charts — Auth + Core APIs

For each service that has no existing chart (from Task 5 audit), run the scaffold script and customize `values.yaml`.

**Files (per service):**
- Create: `charts/<service>/Chart.yaml`
- Create: `charts/<service>/values.yaml`
- Create: `charts/<service>/templates/_helpers.tpl`
- Create: `charts/<service>/templates/deployment.yaml`
- Create: `charts/<service>/templates/service.yaml`

- [ ] **Step 1: Scaffold treetracker-auth**

```bash
bash scripts/scaffold-chart.sh treetracker-auth greenstand/treetracker-auth 3000
```

Edit `charts/treetracker-auth/values.yaml` — replace the `env: []` section:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: KEYCLOAK_URL
    value: "http://greenstand-keycloak:8080"
```

- [ ] **Step 2: Scaffold treetracker-admin-api**

```bash
bash scripts/scaffold-chart.sh treetracker-admin-api greenstand/treetracker-admin-api 3000
```

Edit `charts/treetracker-admin-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AUTH_URL
    value: "http://greenstand-treetracker-auth:80"
```

- [ ] **Step 3: Scaffold treetracker-field-data**

```bash
bash scripts/scaffold-chart.sh treetracker-field-data greenstand/treetracker-field-data 3000
```

Edit `charts/treetracker-field-data/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AWS_ENDPOINT
    value: "http://greenstand-localstack:4566"
  - name: AWS_REGION
    value: "us-east-1"
  - name: AWS_ACCESS_KEY_ID
    value: "test"
  - name: AWS_SECRET_ACCESS_KEY
    value: "test"
```

- [ ] **Step 4: Scaffold treetracker-wallet-api**

```bash
bash scripts/scaffold-chart.sh treetracker-wallet-api greenstand/treetracker-wallet-api 3000
```

Edit `charts/treetracker-wallet-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: KEYCLOAK_URL
    value: "http://greenstand-keycloak:8080"
```

- [ ] **Step 5: Scaffold treetracker-messaging-api**

```bash
bash scripts/scaffold-chart.sh treetracker-messaging-api greenstand/treetracker-messaging-api 3000
```

Edit `charts/treetracker-messaging-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 6: Scaffold treetracker-stakeholder-api**

```bash
bash scripts/scaffold-chart.sh treetracker-stakeholder-api greenstand/treetracker-stakeholder-api 3000
```

Edit `charts/treetracker-stakeholder-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 7: Scaffold treetracker-reporting**

```bash
bash scripts/scaffold-chart.sh treetracker-reporting greenstand/treetracker-reporting 3000
```

Edit `charts/treetracker-reporting/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 8: Scaffold treetracker-like**

```bash
bash scripts/scaffold-chart.sh treetracker-like greenstand/treetracker-like 3000
```

Edit `charts/treetracker-like/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 9: Scaffold treetracker-api**

```bash
bash scripts/scaffold-chart.sh treetracker-api greenstand/treetracker-api 3000
```

Edit `charts/treetracker-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 10: Lint all new charts**

```bash
for d in charts/treetracker-auth charts/treetracker-admin-api charts/treetracker-field-data \
          charts/treetracker-wallet-api charts/treetracker-messaging-api \
          charts/treetracker-stakeholder-api charts/treetracker-reporting \
          charts/treetracker-like charts/treetracker-api; do
  helm lint "$d" && echo "OK: $d"
done
```
Expected: All `OK: charts/<name>`.

- [ ] **Step 11: Commit**

```bash
git add charts/treetracker-auth charts/treetracker-admin-api charts/treetracker-field-data \
        charts/treetracker-wallet-api charts/treetracker-messaging-api \
        charts/treetracker-stakeholder-api charts/treetracker-reporting \
        charts/treetracker-like charts/treetracker-api
git commit -m "feat: scaffold Helm charts for auth and core API services"
```

---

## Task 7: Scaffold Charts — Data + Pipeline Services

- [ ] **Step 1: Scaffold treetracker-grower-account-query**

```bash
bash scripts/scaffold-chart.sh treetracker-grower-account-query greenstand/treetracker-grower-account-query 3000
```

Edit `charts/treetracker-grower-account-query/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 2: Scaffold images-api**

```bash
bash scripts/scaffold-chart.sh images-api greenstand/images-api 3000
```

Edit `charts/images-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AWS_ENDPOINT
    value: "http://greenstand-localstack:4566"
  - name: AWS_REGION
    value: "us-east-1"
  - name: AWS_ACCESS_KEY_ID
    value: "test"
  - name: AWS_SECRET_ACCESS_KEY
    value: "test"
  - name: S3_BUCKET
    value: "treetracker-images-local"
```

- [ ] **Step 3: Scaffold treetracker-tile-server**

```bash
bash scripts/scaffold-chart.sh treetracker-tile-server greenstand/treetracker-map-tile-server 3000
```

Edit `charts/treetracker-tile-server/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 4: Scaffold treetracker-tile-server-next**

```bash
bash scripts/scaffold-chart.sh treetracker-tile-server-next greenstand/treetracker-map-tile-server 3000
```

Edit `charts/treetracker-tile-server-next/values.yaml`:

```yaml
# This runs the next-gen tile server from the same repo, different config
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 5: Scaffold treetracker-denormalization**

```bash
bash scripts/scaffold-chart.sh treetracker-denormalization greenstand/treetracker-denormalization 3000
```

Edit `charts/treetracker-denormalization/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 6: Scaffold bulk-pack-consumer**

```bash
bash scripts/scaffold-chart.sh bulk-pack-consumer greenstand/bulk-pack-consumer 3000
```

Edit `charts/bulk-pack-consumer/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AWS_ENDPOINT
    value: "http://greenstand-localstack:4566"
  - name: AWS_REGION
    value: "us-east-1"
  - name: AWS_ACCESS_KEY_ID
    value: "test"
  - name: AWS_SECRET_ACCESS_KEY
    value: "test"
  - name: S3_BUCKET
    value: "treetracker-bulk-pack-local"
  - name: SQS_QUEUE_URL
    value: "http://greenstand-localstack:4566/000000000000/treetracker-bulk-pack"
```

- [ ] **Step 7: Scaffold bulk-pack-transformer**

```bash
bash scripts/scaffold-chart.sh bulk-pack-transformer greenstand/bulk-pack-transformer 3000
```

Edit `charts/bulk-pack-transformer/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AWS_ENDPOINT
    value: "http://greenstand-localstack:4566"
  - name: AWS_REGION
    value: "us-east-1"
  - name: AWS_ACCESS_KEY_ID
    value: "test"
  - name: AWS_SECRET_ACCESS_KEY
    value: "test"
```

- [ ] **Step 8: Scaffold bulk-pack-transformer-v2**

```bash
bash scripts/scaffold-chart.sh bulk-pack-transformer-v2 greenstand/bulk-pack-transformer 3000
```

Edit `charts/bulk-pack-transformer-v2/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AWS_ENDPOINT
    value: "http://greenstand-localstack:4566"
  - name: AWS_REGION
    value: "us-east-1"
  - name: AWS_ACCESS_KEY_ID
    value: "test"
  - name: AWS_SECRET_ACCESS_KEY
    value: "test"
```

- [ ] **Step 9: Scaffold bulk-pack-processor**

```bash
bash scripts/scaffold-chart.sh bulk-pack-processor greenstand/bulk-pack-processor 3000
```

Edit `charts/bulk-pack-processor/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: AWS_ENDPOINT
    value: "http://greenstand-localstack:4566"
  - name: AWS_REGION
    value: "us-east-1"
  - name: AWS_ACCESS_KEY_ID
    value: "test"
  - name: AWS_SECRET_ACCESS_KEY
    value: "test"
```

- [ ] **Step 10: Scaffold webmap-query-service-consumer**

```bash
bash scripts/scaffold-chart.sh webmap-query-service-consumer greenstand/webmap-query-service-consumer 3000
```

Edit `charts/webmap-query-service-consumer/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 11: Lint all**

```bash
for d in charts/treetracker-grower-account-query charts/images-api \
          charts/treetracker-tile-server charts/treetracker-tile-server-next \
          charts/treetracker-denormalization charts/bulk-pack-consumer \
          charts/bulk-pack-transformer charts/bulk-pack-transformer-v2 \
          charts/bulk-pack-processor charts/webmap-query-service-consumer; do
  helm lint "$d" && echo "OK: $d"
done
```

- [ ] **Step 12: Commit**

```bash
git add charts/treetracker-grower-account-query charts/images-api \
        charts/treetracker-tile-server charts/treetracker-tile-server-next \
        charts/treetracker-denormalization charts/bulk-pack-consumer \
        charts/bulk-pack-transformer charts/bulk-pack-transformer-v2 \
        charts/bulk-pack-processor charts/webmap-query-service-consumer
git commit -m "feat: scaffold Helm charts for data and pipeline services"
```

---

## Task 8: Scaffold Charts — Webmap, PostgREST, and Gateway

PostgREST has no upstream Helm chart, so we create one from scratch. It requires a few extra env vars.

- [ ] **Step 1: Scaffold treetracker-query-api**

```bash
bash scripts/scaffold-chart.sh treetracker-query-api greenstand/treetracker-query-api 3000
```

Edit `charts/treetracker-query-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 2: Scaffold map-config-api**

```bash
bash scripts/scaffold-chart.sh map-config-api greenstand/map-config-api 3000
```

Edit `charts/map-config-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 3: Create PostgREST chart manually** (no upstream Helm chart exists)

```bash
mkdir -p charts/postgrest/templates
cp charts/_base/templates/_helpers.tpl charts/postgrest/templates/
cp charts/_base/templates/deployment.yaml charts/postgrest/templates/
cp charts/_base/templates/service.yaml charts/postgrest/templates/
```

Create `charts/postgrest/Chart.yaml`:

```yaml
apiVersion: v2
name: postgrest
description: PostgREST — REST API for PostgreSQL
type: application
version: 0.1.0
appVersion: "12.0"
```

Create `charts/postgrest/values.yaml`:

```yaml
replicaCount: 2

image:
  repository: postgrest/postgrest
  tag: v12.0.2
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 3000

env:
  - name: PGRST_DB_URI
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: PGRST_DB_SCHEMA
    value: "public"
  - name: PGRST_DB_ANON_ROLE
    value: "treetracker"
  - name: PGRST_SERVER_PORT
    value: "3000"

resources: {}
```

- [ ] **Step 4: Scaffold treetracker-gateway**

```bash
bash scripts/scaffold-chart.sh treetracker-gateway greenstand/treetracker-gateway 3000
```

If the repo name `treetracker-gateway` is incorrect (git submodule add failed in Task 4), correct the image repository to match the actual repo name.

Edit `charts/treetracker-gateway/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
```

- [ ] **Step 5: Lint all**

```bash
for d in charts/treetracker-query-api charts/map-config-api charts/postgrest charts/treetracker-gateway; do
  helm lint "$d" && echo "OK: $d"
done
```

- [ ] **Step 6: Commit**

```bash
git add charts/treetracker-query-api charts/map-config-api charts/postgrest charts/treetracker-gateway
git commit -m "feat: scaffold Helm charts for webmap, postgrest, and gateway services"
```

---

## Task 9: Scaffold Charts — Client Apps + Wallet Monorepo

Frontend client apps are served as static files — their Deployment runs a Node.js server or nginx. Port may differ; check each service's Dockerfile.

- [ ] **Step 1: Scaffold treetracker-admin-client**

```bash
bash scripts/scaffold-chart.sh treetracker-admin-client greenstand/treetracker-admin-client 8080
```

Edit `charts/treetracker-admin-client/values.yaml`:

```yaml
env:
  - name: REACT_APP_API_ROOT
    value: "http://greenstand-treetracker-admin-api:80"
```

- [ ] **Step 2: Scaffold treetracker-wallet-app**

```bash
bash scripts/scaffold-chart.sh treetracker-wallet-app greenstand/treetracker-wallet-app 8080
```

Edit `charts/treetracker-wallet-app/values.yaml`:

```yaml
env:
  - name: REACT_APP_WALLET_API_ROOT
    value: "http://greenstand-treetracker-wallet-api:80"
```

- [ ] **Step 3: Scaffold treetracker-web-map-client**

```bash
bash scripts/scaffold-chart.sh treetracker-web-map-client greenstand/treetracker-web-map-client 8080
```

Edit `charts/treetracker-web-map-client/values.yaml`:

```yaml
env:
  - name: REACT_APP_QUERY_API_ROOT
    value: "http://greenstand-treetracker-query-api:80"
  - name: REACT_APP_MAP_CONFIG_API
    value: "http://greenstand-map-config-api:80"
```

- [ ] **Step 4: Scaffold wallet-monorepo-user-api**

```bash
bash scripts/scaffold-chart.sh wallet-monorepo-user-api greenstand/treetracker-wallet 3000
```

Edit `charts/wallet-monorepo-user-api/values.yaml`:

```yaml
env:
  - name: DATABASE_URL
    value: "postgresql://treetracker:treetracker@greenstand-postgres:5432/treetracker"
  - name: KEYCLOAK_URL
    value: "http://greenstand-keycloak:8080"
```

- [ ] **Step 5: Lint all**

```bash
for d in charts/treetracker-admin-client charts/treetracker-wallet-app \
          charts/treetracker-web-map-client charts/wallet-monorepo-user-api; do
  helm lint "$d" && echo "OK: $d"
done
```

- [ ] **Step 6: Commit**

```bash
git add charts/treetracker-admin-client charts/treetracker-wallet-app \
        charts/treetracker-web-map-client charts/wallet-monorepo-user-api
git commit -m "feat: scaffold Helm charts for client apps and wallet monorepo"
```

---

## Task 10: Airflow Standalone Configuration

Configure Airflow to run in LocalExecutor (standalone) mode targeting ~500MB RAM by disabling all cluster components.

**Files:**
- Modify: `values.yaml` (Airflow section already exists — refine it)
- Modify: `values/local.yaml` (add Airflow resource limits)

- [ ] **Step 1: Update `values.yaml` Airflow section**

Replace the existing `airflow:` block in `values.yaml`:

```yaml
airflow:
  enabled: true
  executor: LocalExecutor
  webserverSecretKey: "change-me-in-production"

  scheduler:
    replicas: 1
    resources:
      requests:
        memory: 256Mi
        cpu: 100m
      limits:
        memory: 512Mi

  webserver:
    replicas: 1
    resources:
      requests:
        memory: 128Mi
        cpu: 100m
      limits:
        memory: 256Mi

  workers:
    replicas: 0

  flower:
    enabled: false

  redis:
    enabled: false

  pgbouncer:
    enabled: false

  statsd:
    enabled: false

  postgresql:
    enabled: false  # use the umbrella postgres

  data:
    metadataConnection:
      user: treetracker
      pass: treetracker
      host: greenstand-postgres
      port: 5432
      db: airflow
      protocol: postgresql

  dags:
    gitSync:
      enabled: false
    persistence:
      enabled: false

  logs:
    persistence:
      enabled: false
```

- [ ] **Step 2: Add Airflow resource limits to `values/local.yaml`**

Append to `values/local.yaml`:

```yaml
# Airflow — LocalExecutor standalone, target ~500MB total
airflow:
  scheduler:
    resources:
      limits:
        memory: 300Mi
  webserver:
    resources:
      limits:
        memory: 200Mi
```

- [ ] **Step 3: Validate**

```bash
helm dependency update
helm template greenstand . -f values/local.yaml | grep -A5 "airflow"
```
Expected: Template renders without errors. Airflow sections show LocalExecutor.

- [ ] **Step 4: Commit**

```bash
git add values.yaml values/local.yaml
git commit -m "feat: configure Airflow in LocalExecutor standalone mode (~500MB)"
```

---

## Task 11: LocalStack Configuration + S3 Seeding Script

Configure LocalStack and create a script to pre-seed the S3 buckets and SQS queues that services expect.

**Files:**
- Modify: `values/local.yaml` (LocalStack config)
- Create: `scripts/seed-localstack.sh`

- [ ] **Step 1: Update LocalStack config in `values/local.yaml`**

Replace the existing `localstack:` block:

```yaml
localstack:
  enabled: true
  startServices: "s3,sqs,sns"
  persistence:
    enabled: false
  resources:
    limits:
      memory: 512Mi
```

- [ ] **Step 2: Create `scripts/seed-localstack.sh`**

```bash
cat > scripts/seed-localstack.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="http://localhost:4566"
REGION="us-east-1"
AWS="aws --endpoint-url=$ENDPOINT --region=$REGION"

echo "Waiting for LocalStack to be ready..."
until $AWS s3 ls &>/dev/null 2>&1; do
  sleep 2
done

echo "Creating S3 buckets..."
$AWS s3 mb s3://treetracker-images-local 2>/dev/null || true
$AWS s3 mb s3://treetracker-bulk-pack-local 2>/dev/null || true

echo "Creating SQS queues..."
$AWS sqs create-queue --queue-name treetracker-bulk-pack 2>/dev/null || true
$AWS sqs create-queue --queue-name treetracker-field-data 2>/dev/null || true

echo "Creating S3 → SQS event notification for bulk-pack bucket..."
QUEUE_ARN=$($AWS sqs get-queue-attributes \
  --queue-url "$ENDPOINT/000000000000/treetracker-bulk-pack" \
  --attribute-names QueueArn \
  --query Attributes.QueueArn --output text)

$AWS s3api put-bucket-notification-configuration \
  --bucket treetracker-bulk-pack-local \
  --notification-configuration "{
    \"QueueConfigurations\": [{
      \"QueueArn\": \"$QUEUE_ARN\",
      \"Events\": [\"s3:ObjectCreated:*\"]
    }]
  }" 2>/dev/null || true

echo "LocalStack seeded successfully."
SCRIPT
chmod +x scripts/seed-localstack.sh
```

- [ ] **Step 3: Add seed target to Makefile**

Add this target to `Makefile`:

```makefile
seed:
	bash scripts/seed-localstack.sh
```

- [ ] **Step 4: Commit**

```bash
git add values/local.yaml scripts/seed-localstack.sh Makefile
git commit -m "feat: configure LocalStack and add S3/SQS seeding script"
```

---

## Task 12: Port-Forward Helper for LocalStack Access

The seed script in Task 11 accesses LocalStack via `localhost:4566`. When running in k3s, LocalStack is only reachable at that address if we port-forward from k3s. Add a port-forward helper.

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Add port-forward target to Makefile**

Add to `Makefile`:

```makefile
port-forward:
	kubectl port-forward svc/greenstand-localstack 4566:4566 &
	kubectl port-forward svc/greenstand-postgres 5432:5432 &

seed: port-forward
	sleep 3
	bash scripts/seed-localstack.sh
```

- [ ] **Step 2: Commit**

```bash
git add Makefile
git commit -m "feat: add port-forward and seed Makefile targets"
```

---

## Task 13: Finalize Chart.yaml — Add All Service Dependencies

Add every service chart as a dependency in the umbrella `Chart.yaml`.

**Files:**
- Modify: `Chart.yaml`

- [ ] **Step 1: Append service dependencies to `Chart.yaml`**

Add the following `dependencies` entries after the infrastructure block. For services that had existing charts in their submodule (found in Task 5), use `file://services/<name>/charts/<chart-name>`. For all others, use `file://charts/<name>`.

```yaml
  # Auth
  - name: treetracker-auth
    version: "0.1.0"
    repository: "file://charts/treetracker-auth"

  # Core APIs
  - name: treetracker-admin-api
    version: "0.1.0"
    repository: "file://charts/treetracker-admin-api"

  - name: treetracker-field-data
    version: "0.1.0"
    repository: "file://charts/treetracker-field-data"

  - name: treetracker-wallet-api
    version: "0.1.0"
    repository: "file://charts/treetracker-wallet-api"

  - name: treetracker-messaging-api
    version: "0.1.0"
    repository: "file://charts/treetracker-messaging-api"

  - name: treetracker-stakeholder-api
    version: "0.1.0"
    repository: "file://charts/treetracker-stakeholder-api"

  - name: treetracker-reporting
    version: "0.1.0"
    repository: "file://charts/treetracker-reporting"

  - name: treetracker-like
    version: "0.1.0"
    repository: "file://charts/treetracker-like"

  - name: treetracker-api
    version: "0.1.0"
    repository: "file://charts/treetracker-api"

  # Data + Pipeline
  - name: treetracker-grower-account-query
    version: "0.1.0"
    repository: "file://charts/treetracker-grower-account-query"

  - name: images-api
    version: "0.1.0"
    repository: "file://charts/images-api"

  - name: treetracker-tile-server
    version: "0.1.0"
    repository: "file://charts/treetracker-tile-server"

  - name: treetracker-tile-server-next
    version: "0.1.0"
    repository: "file://charts/treetracker-tile-server-next"

  - name: treetracker-denormalization
    version: "0.1.0"
    repository: "file://charts/treetracker-denormalization"

  - name: bulk-pack-consumer
    version: "0.1.0"
    repository: "file://charts/bulk-pack-consumer"

  - name: bulk-pack-transformer
    version: "0.1.0"
    repository: "file://charts/bulk-pack-transformer"

  - name: bulk-pack-transformer-v2
    version: "0.1.0"
    repository: "file://charts/bulk-pack-transformer-v2"

  - name: bulk-pack-processor
    version: "0.1.0"
    repository: "file://charts/bulk-pack-processor"

  - name: webmap-query-service-consumer
    version: "0.1.0"
    repository: "file://charts/webmap-query-service-consumer"

  # Webmap
  - name: treetracker-query-api
    version: "0.1.0"
    repository: "file://charts/treetracker-query-api"

  - name: postgrest
    version: "0.1.0"
    repository: "file://charts/postgrest"

  - name: map-config-api
    version: "0.1.0"
    repository: "file://charts/map-config-api"

  # Gateway
  - name: treetracker-gateway
    version: "0.1.0"
    repository: "file://charts/treetracker-gateway"

  # Clients
  - name: treetracker-admin-client
    version: "0.1.0"
    repository: "file://charts/treetracker-admin-client"

  - name: treetracker-wallet-app
    version: "0.1.0"
    repository: "file://charts/treetracker-wallet-app"

  - name: treetracker-web-map-client
    version: "0.1.0"
    repository: "file://charts/treetracker-web-map-client"

  - name: wallet-monorepo-user-api
    version: "0.1.0"
    repository: "file://charts/wallet-monorepo-user-api"
```

- [ ] **Step 2: Run `helm dependency update`**

```bash
helm dependency update
```
Expected: All charts resolved and packaged into `charts/*.tgz`. No errors.

- [ ] **Step 3: Lint the full umbrella**

```bash
helm lint . -f values/local.yaml
```
Expected: `1 chart(s) linted, 0 chart(s) failed`

- [ ] **Step 4: Commit**

```bash
git add Chart.yaml Chart.lock charts/*.tgz
git commit -m "feat: add all service dependencies to umbrella Chart.yaml"
```

---

## Task 14: Finalize values.yaml + values/local.yaml — All Service Defaults

Add default values for every service to `values.yaml` and local overrides (replicas=1) to `values/local.yaml`.

**Files:**
- Modify: `values.yaml`
- Modify: `values/local.yaml`

- [ ] **Step 1: Append service defaults to `values.yaml`**

Append to `values.yaml`:

```yaml
# --- Application Service Defaults ---
treetracker-auth:
  replicaCount: 2

treetracker-admin-api:
  replicaCount: 2

treetracker-field-data:
  replicaCount: 2

treetracker-wallet-api:
  replicaCount: 2

treetracker-messaging-api:
  replicaCount: 2

treetracker-stakeholder-api:
  replicaCount: 2

treetracker-reporting:
  replicaCount: 2

treetracker-like:
  replicaCount: 2

treetracker-api:
  replicaCount: 2

treetracker-grower-account-query:
  replicaCount: 2

images-api:
  replicaCount: 2

treetracker-tile-server:
  replicaCount: 2

treetracker-tile-server-next:
  replicaCount: 2

treetracker-denormalization:
  replicaCount: 2

bulk-pack-consumer:
  replicaCount: 2

bulk-pack-transformer:
  replicaCount: 2

bulk-pack-transformer-v2:
  replicaCount: 2

bulk-pack-processor:
  replicaCount: 2

webmap-query-service-consumer:
  replicaCount: 2

treetracker-query-api:
  replicaCount: 2

postgrest:
  replicaCount: 2

map-config-api:
  replicaCount: 2

treetracker-gateway:
  replicaCount: 2

treetracker-admin-client:
  replicaCount: 2

treetracker-wallet-app:
  replicaCount: 2

treetracker-web-map-client:
  replicaCount: 2

wallet-monorepo-user-api:
  replicaCount: 2
```

- [ ] **Step 2: Append replica overrides to `values/local.yaml`**

Append to `values/local.yaml`:

```yaml
# --- All services: 1 replica locally ---
treetracker-auth:
  replicaCount: 1
treetracker-admin-api:
  replicaCount: 1
treetracker-field-data:
  replicaCount: 1
treetracker-wallet-api:
  replicaCount: 1
treetracker-messaging-api:
  replicaCount: 1
treetracker-stakeholder-api:
  replicaCount: 1
treetracker-reporting:
  replicaCount: 1
treetracker-like:
  replicaCount: 1
treetracker-api:
  replicaCount: 1
treetracker-grower-account-query:
  replicaCount: 1
images-api:
  replicaCount: 1
treetracker-tile-server:
  replicaCount: 1
treetracker-tile-server-next:
  replicaCount: 1
treetracker-denormalization:
  replicaCount: 1
bulk-pack-consumer:
  replicaCount: 1
bulk-pack-transformer:
  replicaCount: 1
bulk-pack-transformer-v2:
  replicaCount: 1
bulk-pack-processor:
  replicaCount: 1
webmap-query-service-consumer:
  replicaCount: 1
treetracker-query-api:
  replicaCount: 1
postgrest:
  replicaCount: 1
map-config-api:
  replicaCount: 1
treetracker-gateway:
  replicaCount: 1
treetracker-admin-client:
  replicaCount: 1
treetracker-wallet-app:
  replicaCount: 1
treetracker-web-map-client:
  replicaCount: 1
wallet-monorepo-user-api:
  replicaCount: 1
```

- [ ] **Step 3: Dry-run the full install**

```bash
helm install greenstand . -f values/local.yaml --dry-run 2>&1 | tail -20
```
Expected: Large YAML output with no errors. Last line should not contain "Error".

- [ ] **Step 4: Commit**

```bash
git add values.yaml values/local.yaml
git commit -m "feat: add default and local replica values for all services"
```

---

## Task 15: Skaffold Profiles — Local Image Builds

One Skaffold profile per service. Running `skaffold dev --profile=<name>` builds the image from that service's submodule and hot-swaps it into the running cluster.

**Files:**
- Create: `skaffold.yaml`

- [ ] **Step 1: Create `skaffold.yaml`**

```yaml
apiVersion: skaffold/v4beta9
kind: Config
metadata:
  name: greenstand

profiles:
  - name: treetracker-auth
    build:
      artifacts:
        - image: localhost:5000/treetracker-auth
          context: services/treetracker-auth
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-auth.image.repository: localhost:5000/treetracker-auth
              treetracker-auth.image.tag: "{{.IMAGE_TAG_treetracker_auth}}"

  - name: treetracker-admin-api
    build:
      artifacts:
        - image: localhost:5000/treetracker-admin-api
          context: services/treetracker-admin-api
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-admin-api.image.repository: localhost:5000/treetracker-admin-api
              treetracker-admin-api.image.tag: "{{.IMAGE_TAG_treetracker_admin_api}}"

  - name: treetracker-field-data
    build:
      artifacts:
        - image: localhost:5000/treetracker-field-data
          context: services/treetracker-field-data
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-field-data.image.repository: localhost:5000/treetracker-field-data
              treetracker-field-data.image.tag: "{{.IMAGE_TAG_treetracker_field_data}}"

  - name: treetracker-wallet-api
    build:
      artifacts:
        - image: localhost:5000/treetracker-wallet-api
          context: services/treetracker-wallet-api
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-wallet-api.image.repository: localhost:5000/treetracker-wallet-api
              treetracker-wallet-api.image.tag: "{{.IMAGE_TAG_treetracker_wallet_api}}"

  - name: treetracker-messaging-api
    build:
      artifacts:
        - image: localhost:5000/treetracker-messaging-api
          context: services/treetracker-messaging-api
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-messaging-api.image.repository: localhost:5000/treetracker-messaging-api
              treetracker-messaging-api.image.tag: "{{.IMAGE_TAG_treetracker_messaging_api}}"

  - name: treetracker-stakeholder-api
    build:
      artifacts:
        - image: localhost:5000/treetracker-stakeholder-api
          context: services/treetracker-stakeholder-api
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-stakeholder-api.image.repository: localhost:5000/treetracker-stakeholder-api
              treetracker-stakeholder-api.image.tag: "{{.IMAGE_TAG_treetracker_stakeholder_api}}"

  - name: treetracker-api
    build:
      artifacts:
        - image: localhost:5000/treetracker-api
          context: services/treetracker-api
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-api.image.repository: localhost:5000/treetracker-api
              treetracker-api.image.tag: "{{.IMAGE_TAG_treetracker_api}}"

  - name: bulk-pack-consumer
    build:
      artifacts:
        - image: localhost:5000/bulk-pack-consumer
          context: services/bulk-pack-consumer
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              bulk-pack-consumer.image.repository: localhost:5000/bulk-pack-consumer
              bulk-pack-consumer.image.tag: "{{.IMAGE_TAG_bulk_pack_consumer}}"

  - name: treetracker-admin-client
    build:
      artifacts:
        - image: localhost:5000/treetracker-admin-client
          context: services/treetracker-admin-client
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-admin-client.image.repository: localhost:5000/treetracker-admin-client
              treetracker-admin-client.image.tag: "{{.IMAGE_TAG_treetracker_admin_client}}"

  - name: treetracker-web-map-client
    build:
      artifacts:
        - image: localhost:5000/treetracker-web-map-client
          context: services/treetracker-web-map-client
    deploy:
      helm:
        releases:
          - name: greenstand
            chartPath: .
            valuesFiles: [values/local.yaml]
            setValueTemplates:
              treetracker-web-map-client.image.repository: localhost:5000/treetracker-web-map-client
              treetracker-web-map-client.image.tag: "{{.IMAGE_TAG_treetracker_web_map_client}}"
```

Note: Add profiles for remaining services by copying the pattern above, substituting the service name. The Skaffold `IMAGE_TAG` template variable replaces hyphens with underscores automatically.

- [ ] **Step 2: Validate skaffold config**

```bash
skaffold config list
skaffold build --profile=treetracker-admin-api --dry-run 2>&1 | head -10
```
Expected: No parse errors. Dry-run shows the build artifact without actually building.

- [ ] **Step 3: Commit**

```bash
git add skaffold.yaml
git commit -m "feat: add Skaffold profiles for per-service local image builds"
```

---

## Task 16: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Rewrite `README.md`**

```markdown
# Greenstand Monorepo

Deploys the full Greenstand platform into a local k3s cluster.

## Prerequisites

- Docker
- [Helm 3.14+](https://helm.sh/docs/intro/install/)
- [Skaffold 2.10+](https://skaffold.dev/docs/install/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) (for LocalStack seeding)

## First-time Setup

```bash
make setup          # installs k3s + local registry (requires sudo)
make submodules     # pulls all service repos
```

## Running the Stack

```bash
make up             # helm install — deploys everything
make seed           # pre-seeds LocalStack S3 buckets and SQS queues
```

## Developing a Single Service

```bash
make dev SERVICE=treetracker-admin-api
```

Builds the image from `services/treetracker-admin-api/`, pushes to the local registry, and hot-swaps the deployment. Ctrl+C to stop.

## Tearing Down

```bash
make down
```

## Running E2e Tests

```bash
make e2e
```

## Available Services

| Service | Local URL (via Ambassador) |
|---|---|
| Admin API | http://localhost/admin-api |
| Wallet API | http://localhost/wallet-api |
| Web Map | http://localhost/ |
| Admin Client | http://localhost/admin |

(Ambassador routing rules are defined in the ambassador namespace.)

## Adding a New Service

```bash
git submodule add https://github.com/Greenstand/<repo> services/<name>
bash scripts/scaffold-chart.sh <name> greenstand/<image> <port>
# Add to Chart.yaml dependencies, values.yaml defaults, values/local.yaml overrides, skaffold.yaml profiles
helm dependency update
```
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: update README with full usage instructions"
```

---

## Task 17: Full Stack Smoke Test

With k3s running (after `make setup`), install the full stack and verify all pods start.

**Files:** None created.

- [ ] **Step 1: Run `make up`**

```bash
make up
```
Expected: Helm install completes without errors. May take 3–5 minutes for images to pull.

- [ ] **Step 2: Watch pods come up**

```bash
kubectl get pods -A -w
```
Expected: All pods reach `Running` status. Investigate any `CrashLoopBackOff` or `ImagePullBackOff` — these indicate misconfigured image names or missing env vars. Fix the relevant chart's `values.yaml` and run `make upgrade`.

- [ ] **Step 3: Verify postgres is reachable**

```bash
kubectl port-forward svc/greenstand-postgres 5432:5432 &
psql postgresql://treetracker:treetracker@localhost:5432/treetracker -c '\l'
```
Expected: Lists databases including `treetracker`.

- [ ] **Step 4: Verify LocalStack is reachable**

```bash
kubectl port-forward svc/greenstand-localstack 4566:4566 &
aws --endpoint-url=http://localhost:4566 s3 ls
```
Expected: Empty bucket list (seed not run yet).

- [ ] **Step 5: Run seed**

```bash
make seed
aws --endpoint-url=http://localhost:4566 s3 ls
```
Expected: Shows `treetracker-images-local` and `treetracker-bulk-pack-local`.

- [ ] **Step 6: Tear down and verify clean**

```bash
make down
kubectl get pods -A | grep greenstand
```
Expected: No greenstand pods remaining.

- [ ] **Step 7: Commit any fixes from this step**

```bash
git add -p  # stage only intentional changes
git commit -m "fix: correct chart values from smoke test findings"
```

---

## Task 18: E2e Test Harness Scaffold

Create the `make e2e` entry point. Full test suite authorship is out of scope here — this scaffolds the runner so it can be expanded.

**Files:**
- Create: `scripts/e2e.sh`
- Modify: `Makefile`

- [ ] **Step 1: Create `scripts/e2e.sh`**

```bash
cat > scripts/e2e.sh << 'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

echo "=== Greenstand E2e Test Runner ==="

# Ensure stack is up
if ! helm status greenstand &>/dev/null; then
  echo "Stack not running. Starting..."
  helm dependency update
  helm install greenstand . -f values/local.yaml
  echo "Waiting for pods..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/managed-by=Helm \
    --timeout=300s --all-namespaces 2>/dev/null || true
fi

# Seed LocalStack
bash scripts/seed-localstack.sh

# Run tests
# TODO: replace this placeholder with actual test invocation
# e.g.: npx jest --testPathPattern=e2e/ or pytest tests/e2e/
echo "No test suite configured yet. Add test invocation to scripts/e2e.sh"
echo "Tests passed (placeholder)."
SCRIPT
chmod +x scripts/e2e.sh
```

- [ ] **Step 2: Verify `make e2e` runs without error (stack already down)**

```bash
make e2e
```
Expected: Stack spins up, seeds LocalStack, prints placeholder message.

- [ ] **Step 3: Commit**

```bash
git add scripts/e2e.sh Makefile
git commit -m "feat: add e2e test harness scaffold"
```

---

## Spec Coverage Check

| Spec requirement | Task |
|---|---|
| Git submodules for all services | Task 4 |
| Umbrella Helm chart | Tasks 3, 13 |
| values/local.yaml with single postgres + replicas=1 | Tasks 3, 14 |
| LocalStack for S3/SQS/SNS | Tasks 11, 12 |
| Airflow standalone (LocalExecutor, ~500MB) | Task 10 |
| Removed services (RabbitMQ, OpenProject, etc.) | Not in Chart.yaml — confirmed absent |
| Skaffold profiles for local image builds | Task 15 |
| make setup / up / down / dev / e2e / seed targets | Tasks 1, 12, 16 |
| Blockchain stack (TODO) | Not implemented — explicitly deferred |
| k3s local registry at localhost:5000 | Task 1 |
| README with usage | Task 16 |
