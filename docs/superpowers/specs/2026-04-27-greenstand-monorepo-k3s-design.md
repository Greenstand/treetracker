# Greenstand Monorepo + k3s Local Deployment Design

## Goals

1. **E2e / integration testing** — spin up the full Greenstand stack locally or in CI and run automated tests against it
2. **Local development** — build a service image from source, hot-swap it into k3s, iterate fast
3. **Staging mirror** — reproducible environment using published images (stretch goal once stable)

## Repository Structure

```
treetracker/                        ← this repo (github.com/Greenstand/treetracker)
├── .gitmodules                     ← one entry per service submodule
├── Chart.yaml                      ← umbrella Helm chart
├── values.yaml                     ← defaults (published images, prod-like config)
├── values/
│   ├── local.yaml                  ← local k3s overrides (single postgres, replicas=1, localstack)
│   └── staging.yaml                ← staging-specific overrides
├── charts/                         ← per-service charts for services that don't ship their own
│   └── <service-name>/
├── services/                       ← git submodules
│   ├── treetracker-admin-api/
│   ├── treetracker-wallet-api/
│   ├── treetracker-field-data/
│   └── ...                         ← one submodule per included service
├── skaffold.yaml                   ← one profile per service for local image builds
├── Makefile                        ← thin aliases: make setup, make up, make dev, make down, make e2e
└── docs/
```

Each service chart is either pulled from the submodule (if the service repo contains a `charts/` directory) or maintained directly in this repo under `charts/<service>/`. Third-party/infra charts (postgres, cert-manager, localstack, ambassador, keycloak, airflow) are declared as dependencies using their upstream Helm repos — no submodule needed.

## Services

### Infrastructure (upstream Helm charts, not submodules)

| Service | Chart source | Notes |
|---|---|---|
| PostgreSQL | bitnami/postgresql | Single instance locally (replaces pgpool + HA replicas) |
| LocalStack | localstack/localstack | Emulates S3, SQS, SNS for bulk-pack-consumer |
| cert-manager | cert-manager/cert-manager | TLS |
| sealed-secrets | sealed-secrets/sealed-secrets | Secret management |
| Ambassador | ambassador/ambassador | Ingress / API gateway |
| Keycloak | bitnami/keycloak | Auth |
| Airflow | apache-airflow/airflow | Standalone mode, target ~500MB RAM |
| kubernetes-dashboard | kubernetes/dashboard | Optional, local visibility |

### Application Services (git submodules)

| Namespace | Service | Repo |
|---|---|---|
| ambassador | treetracker-auth | treetracker-auth |
| admin-api | treetracker-admin-api | treetracker-admin-api |
| field-data-api | treetracker-field-data | treetracker-field-data |
| wallet-api | treetracker-wallet-api | treetracker-wallet-api |
| messaging-api | treetracker-messaging-api | treetracker-messaging-api |
| stakeholder-api | treetracker-stakeholder-api | treetracker-stakeholder-api |
| reporting | treetracker-reporting | treetracker-reporting |
| treetracker-like-api | treetracker-like-api | treetracker-like |
| query | treetracker-grower-account-query | treetracker-grower-account-query |
| images-api | images-api | images-api |
| tile-server | treetracker-tile-server | treetracker-map-tile-server |
| tile-server-next | treetracker-tile-server-next | treetracker-map-tile-server |
| treetracker-api | treetracker-api | treetracker-api |
| denormalization | treetracker-denormalization | treetracker-denormalization |
| bulk-pack-services | bulk-pack-consumer | bulk-pack-consumer |
| bulk-pack-services | bulk-pack-transformer | bulk-pack-transformer |
| bulk-pack-services | bulk-pack-transformer-v2 | bulk-pack-transformer-v2 |
| bulk-pack-services | bulk-pack-processor | bulk-pack-processor |
| webmap | treetracker-query-api | treetracker-query-api |
| webmap | postgrest | (upstream chart) |
| webmap | webmap-query-service-consumer | webmap-query-service-consumer |
| webmap-config | treetracker-map-config-api | map-config-api |
| treetracker-clients | admin-simple | treetracker-admin-client |
| treetracker-clients | wallet-simple | treetracker-wallet-app |
| treetracker-clients | web-map-simple | treetracker-web-map-client |
| treetracker-clients | web-map-deploy | treetracker-web-map-client |
| treetracker-gateway | gateway-service-simple | treetracker-gateway |
| treetracker-wallet-monorepo-user-api | wallet-monorepo-user-api | treetracker-wallet |

### Removed

| Service | Reason |
|---|---|
| RabbitMQ | Not actively used; bulk-pack uses S3 events instead |
| OpenProject | No longer in use |
| Prometheus + Loki + Grafana | Observability stack removed to reduce overhead |
| earnings-api | Service no longer needed |
| regions-api | Service no longer needed |
| contract-api | Service no longer needed |
| treetracker-web-map-api | Service no longer needed |
| ArgoCD | Not used locally; direct Helm installs instead |

### TODO (future optional add-on)

- Entire Hyperledger Fabric blockchain stack: hlf-ca, hlf-orderer, hlf-peer-org, treetracker-blockchain-auth
- These are complex to run locally and currently broken in the test cluster; defer until core stack is stable

## Deployment

### Umbrella Helm Chart

`Chart.yaml` declares all services and infra charts as dependencies. A single command installs the full stack:

```bash
helm dependency update
helm install greenstand . -f values/local.yaml
```

`values/local.yaml` sets:
- All services: `replicaCount: 1`
- PostgreSQL: single instance (no pgpool, no replicas)
- LocalStack endpoint substituted for real AWS S3/SQS/SNS URLs
- Airflow: standalone mode (LocalExecutor — tasks run as subprocesses, no flower/redis/worker pods)
- Image tags: `latest` by default, overridable per service

### Local k3s Registry

k3s is configured with a local registry at `localhost:5000` via `/etc/rancher/k3s/registries.yaml`. `make setup` handles this one-time configuration.

## Local Development Workflow

### Full stack up/down

```bash
make setup        # one-time: install k3s, configure local registry
make up           # helm install greenstand . -f values/local.yaml
make down         # helm uninstall greenstand
```

### Developing a single service

```bash
make dev SERVICE=admin-api
# → skaffold dev --profile=admin-api
```

Skaffold builds the image from `services/treetracker-admin-api/`, pushes to `localhost:5000`, and patches the running deployment. All other services continue running from published images.

### Skaffold profile structure (one per service in root `skaffold.yaml`)

```yaml
profiles:
  - name: admin-api
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
              treetracker-admin-api.image.tag: "{{.IMAGE_TAG}}"
```

### E2e testing

```bash
make e2e
# → ensures stack is up → runs test suite → reports results
```

LocalStack is pre-seeded with test S3 buckets on startup. Tests reach services via Ambassador (same path as production clients).

## Makefile Targets

| Target | Description |
|---|---|
| `make setup` | One-time: install k3s, configure local registry |
| `make up` | `helm install greenstand . -f values/local.yaml` |
| `make upgrade` | `helm upgrade greenstand . -f values/local.yaml` |
| `make down` | `helm uninstall greenstand` |
| `make dev SERVICE=<name>` | `skaffold dev --profile=<name>` |
| `make e2e` | Run e2e test suite against local stack |
| `make submodules` | `git submodule update --init --recursive` |

The Makefile is documentation as much as automation — contributors can run the underlying commands directly.
