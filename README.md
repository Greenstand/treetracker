# Greenstand Monorepo

Deploys the full Greenstand platform into a local Kubernetes cluster for local development and e2e testing.

## Prerequisites

**All platforms:**
- [Helm 3.14+](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) (for LocalStack seeding)
- [Skaffold 2.10+](https://skaffold.dev/docs/install/) (for `make dev` only)

**macOS:** [Podman](https://podman.io/docs/installation) + [k3d](https://k3d.io/) (installed via `make setup`)

**Linux:** [k3s](https://k3s.io/) (installed via `make setup`)

## First-time Setup

`make setup` auto-detects your OS:

```bash
make setup          # macOS: installs k3d + creates cluster with local registry
                    # Linux: installs k3s + starts local registry container
make submodules     # pulls all service repos
```

### macOS detail

`make setup` on macOS:
1. Ensures your Podman machine is running
2. Installs k3d via Homebrew if not present (`brew install k3d`)
3. Creates a k3d cluster named `greenstand` with a built-in registry at `localhost:5000`
4. Merges the cluster kubeconfig into `~/.kube/config`

If you prefer to do it manually:
```bash
brew install k3d
podman machine start
k3d cluster create greenstand --registry-create greenstand-registry:0.0.0.0:5000 --wait
k3d kubeconfig merge greenstand --kubeconfig-merge-default
```

To tear down the cluster entirely:
```bash
k3d cluster delete greenstand
```

### Linux detail

`make setup` on Linux installs k3s (requires `sudo`) and starts a local Docker/Podman registry container at `localhost:5000`.

## Running the Stack

```bash
make up             # helm install — deploys the full stack
make seed           # pre-seeds LocalStack S3 buckets and SQS queues
```

## Developing a Single Service

```bash
make dev SERVICE=treetracker-admin-api
```

Builds the image from `services/treetracker-admin-api/`, pushes to the local k3s registry, and hot-swaps only that service. All other services continue running from published images. Press Ctrl+C to stop.

## Tearing Down

```bash
make down
```

## Running E2e Tests

```bash
make e2e
```

## Port Forwarding (for local access to backing services)

```bash
make port-forward   # forwards postgres:5432 and localstack:4566 to localhost
make seed           # seeds LocalStack (includes port-forward)
```

## Available Make Targets

| Target | Description |
|---|---|
| `make setup` | One-time k3s + local registry install |
| `make submodules` | Pull/update all service submodules |
| `make up` | Deploy full stack via helm install |
| `make upgrade` | Upgrade running stack |
| `make down` | Uninstall the stack |
| `make dev SERVICE=<name>` | Build + hot-swap a single service |
| `make lint` | Lint the umbrella chart |
| `make port-forward` | Forward postgres and localstack to localhost |
| `make seed` | Seed LocalStack with S3 buckets and SQS queues |
| `make e2e` | Run e2e test suite |

## Adding a New Service

```bash
git submodule add https://github.com/Greenstand/<repo> services/<name>
bash scripts/scaffold-chart.sh <name> greenstand/<image> <port>
# Then add to: Chart.yaml dependencies, values.yaml, values/local.yaml, skaffold.yaml
DOCKER_CONFIG=.helm-docker-config helm dependency update
```

## Services Included

See `Chart.yaml` for the full list. Excluded (not in the org or retired): `treetracker-gateway`, earnings-api, regions-api, contract-api, RabbitMQ, OpenProject, Prometheus/Grafana/Loki.

## Blockchain Stack

The Hyperledger Fabric stack (hlf-ca, hlf-orderer, hlf-peer-org, treetracker-blockchain-auth) is deferred — it's currently broken in the test cluster. Add as an optional overlay when stable.
