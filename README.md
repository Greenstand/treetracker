# Greenstand Monorepo

Deploys the full Greenstand platform into a local Kubernetes cluster for local development and e2e testing.

## Prerequisites

**All platforms:**
- [Helm 3.14+](https://helm.sh/docs/intro/install/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) (for LocalStack seeding)
- [Skaffold 2.10+](https://skaffold.dev/docs/install/) (for `make dev` only)

**macOS:** [Colima](https://github.com/abiosoft/colima) + [Docker CLI](https://formulae.brew.sh/formula/docker) + [k3d](https://k3d.io/) (k3d installed automatically by `make setup`)

```bash
brew install colima docker k3d
```

> **Note:** If you have Podman's `docker` shim on your PATH (`podman machine`), the real Docker CLI must come first. `make setup` handles this automatically via `/opt/homebrew/opt/docker/bin/docker`.

**Linux:** [k3s](https://k3s.io/) (installed via `make setup`)

## First-time Setup

```bash
make setup          # macOS: starts Colima, creates k3d cluster + local registry
                    # Linux: installs k3s + starts local registry container
make submodules     # pull all service repos (git submodule update --init --recursive)
make build-all      # build local service images and push to the k3d registry
make up             # helm install — deploys the full stack
make seed           # pre-seed LocalStack S3 buckets and SQS queues
```

### macOS detail

`make setup` on macOS:
1. Starts Colima with the Docker runtime (creates `~/.colima/default/docker.sock`)
2. Installs k3d via Homebrew if not present
3. Creates a k3d registry named `greenstand-registry` at `localhost:5000`
4. Creates a k3d cluster named `greenstand` connected to that registry
5. Merges the cluster kubeconfig into `~/.kube/config`

Port 5000 must be free. On macOS, AirPlay Receiver occupies it by default — disable it with:
```bash
sudo defaults write /Library/Preferences/com.apple.controlcenter.plist AirplayRecieverEnabled -bool false
killall ControlCenter
```

To tear down and start fresh:
```bash
make reset   # deletes the k3d cluster and registry, then re-runs setup
```

### Linux detail

`make setup` on Linux installs k3s (requires `sudo`) and starts a local Docker registry container at `localhost:5000`.

## Running the Stack

```bash
make up             # helm install — deploys the full stack
make seed           # pre-seeds LocalStack S3 buckets and SQS queues
```

## Building Service Images

```bash
make build-all      # build all services with local Dockerfiles and push to localhost:5000
make upgrade        # redeploy with the newly built images
```

`make build-all` uses the real Docker CLI against Colima's socket. Images are pushed to the k3d registry and picked up automatically on `make upgrade` via `values/local-images.yaml`.

## Developing a Single Service

```bash
make dev SERVICE=treetracker-admin-api
```

Builds the image from `services/treetracker-admin-api/`, pushes to the local registry, and hot-swaps only that service. All other services continue running. Press Ctrl+C to stop.

## Tearing Down

```bash
make down    # helm uninstall (leaves the cluster running)
make reset   # delete the cluster entirely and re-run setup
```

## Port Forwarding (for local access to backing services)

```bash
make port-forward   # forwards postgres:5432 and localstack:4566 to localhost
make seed           # seeds LocalStack (includes port-forward)
```

## Available Make Targets

| Target | Description |
|---|---|
| `make setup` | One-time cluster + registry setup |
| `make submodules` | Pull/update all service submodules |
| `make build-all` | Build all service images and push to the local registry |
| `make up` | Deploy full stack via helm install |
| `make upgrade` | Upgrade running stack |
| `make down` | Uninstall the stack (keeps cluster) |
| `make reset` | Delete cluster + registry and re-run setup |
| `make dev SERVICE=<name>` | Build + hot-swap a single service |
| `make lint` | Lint the umbrella chart |
| `make port-forward` | Forward postgres and localstack to localhost |
| `make seed` | Seed LocalStack with S3 buckets and SQS queues |
| `make e2e` | Run e2e test suite |

## Service Status

### Working (deploys and runs healthy)

| Service | Notes |
|---|---|
| `treetracker-auth` | |
| `treetracker-admin-api` | |
| `treetracker-field-data` | Requires RabbitMQ (`RABBIT_MQ_URL`) |
| `treetracker-wallet-api` | Requires RSA keypair (`PRIVATE_KEY` / `PUBLIC_KEY`) — local.yaml carries test keys |
| `treetracker-messaging-api` | |
| `treetracker-stakeholder-api` | |
| `treetracker-reporting` | |
| `treetracker-api` | Requires RabbitMQ (`RABBIT_MQ_URL`) |
| `treetracker-earnings-api` | |
| `treetracker-grower-account-query` | |
| `treetracker-contract-api` | |
| `treetracker-regions-api` | |
| `treetracker-query-api` | Requires TypeScript pre-compile step (handled by `build-all`) |
| `treetracker-denormalization` | |
| `treetracker-web-map-api` | |
| `treetracker-web-map-client` | |
| `images-api` | |
| `map-config-api` | |
| `postgrest` | |
| `bulk-pack-consumer` | |
| `bulk-pack-transformer` | |
| `bulk-pack-transformer-v2` | Uses same image as `bulk-pack-transformer` |
| `bulk-pack-processor` | Batch job — exits with code 0 after each run; Kubernetes restarts on backoff |
| `webmap-query-service-consumer` | Requires `node_modules/` + `dist/` pre-built (handled by `build-all`) |
| `postgres` | Bitnami PostgreSQL 18.6 |
| `localstack` | Pinned to OSS image 3.8.1; v4+ requires a license |
| `rabbitmq` | Minimal chart using `rabbitmq:3.13-management-alpine` |

### Not Working — Follow-up Tickets Needed

| Service | Status | Reason / Ticket |
|---|---|---|
| `treetracker-like` | `replicaCount: 0` | Dockerfile references `apps/like/prisma/schema.prisma` which is absent from the submodule checkout. Needs Prisma schema committed or Dockerfile fixed. |
| `treetracker-tile-server` | `replicaCount: 0` | npm dependency (`Windshaft`) is installed from a GitHub URL; git fails inside the Docker build context because `.git` for the submodule is a pointer file, not a full repo. Needs Dockerfile or npm dep fixed upstream. |
| `treetracker-tile-server-next` | `replicaCount: 0` | No local submodule source. Docker Hub image (`greenstand/treetracker-map-tile-server`) is private or does not exist. Needs submodule added or image published. |
| `treetracker-gateway` | `replicaCount: 0` | No local submodule source. Docker Hub image (`greenstand/treetracker-gateway`) is private or does not exist. Needs submodule added or image published. |
| `treetracker-admin-client` | `replicaCount: 0` | Submodule exists but has no `Dockerfile`. Needs a Dockerfile added to the repo. |
| `treetracker-wallet-app` | `replicaCount: 0` | Submodule exists but has no top-level `Dockerfile` (only `apps/user/Dockerfile`). Needs a root-level Dockerfile or chart image path updated. |
| `wallet-monorepo-user-api` | `replicaCount: 0` | No local submodule source. Docker Hub image (`greenstand/treetracker-wallet-monorepo-user-api`) is private or does not exist. Needs submodule added or image published. |

### Known Gaps

- **Database schema:** The `bulk_tree_upload` table is not created by any migration — it was added manually. A migration should be added to one of the services (likely `treetracker-field-data` or `bulk-pack-consumer`).
- **`bulk-pack-processor` restart policy:** This is a batch job running as a Deployment. It exits with code 0 after each run, triggering Kubernetes' backoff timer (up to 5 min between runs). It should be converted to a `CronJob`.
- **LocalStack SQS queues:** Services that poll SQS (`bulk-pack-consumer`, `webmap-query-service-consumer`) see `QueueDoesNotExist` errors until `make seed` is run.
- **DB migrations:** No service auto-runs its database migrations on startup. Migrations must be run manually (e.g., via `kubectl exec` into the postgres pod or a dedicated migration Job).

## Adding a New Service

```bash
git submodule add https://github.com/Greenstand/<repo> services/<name>
bash scripts/scaffold-chart.sh <name> greenstand/<image> <port>
# Then add to: Chart.yaml dependencies, values/local.yaml, values/local-images.yaml
make upgrade
```

## Blockchain Stack

The Hyperledger Fabric stack (hlf-ca, hlf-orderer, hlf-peer-org, treetracker-blockchain-auth) is deferred — it's currently broken in the test cluster. Add as an optional overlay when stable.
