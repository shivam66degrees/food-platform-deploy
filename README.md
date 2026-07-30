# food-platform-deploy

Helm deployment repo for the food delivery platform (CD only). Service code and Docker images live in the seven `food-*-service` polyrepos.

## Layout

```
charts/food-platform/          Umbrella chart
├── Chart.yaml
├── values.yaml                Shared defaults
├── values-local.yaml          Rancher Desktop / local K8s
├── values-gcp.yaml            GKE stub (Artifact Registry, managed ingress)
├── templates/                 Platform-wide resources (JWT secret)
└── charts/                    Subcharts
    ├── infra/                 Postgres (×6) + Kafka + topic init job
    ├── identity/
    ├── catalog/
    ├── order/
    ├── delivery/
    ├── payment/
    ├── notification/
    └── gateway/               Includes optional Ingress

scripts/
├── local-build-images.sh      Build food/*:local images from platform workspace
├── local-deploy.sh            Helm install/upgrade to local cluster
├── local-teardown.sh          Uninstall release (+ optional namespace/PVC cleanup)
├── verify-k8s-health.sh       Actuator health checks on all 7 services in K8s
└── env.example                Optional environment overrides

docs/
└── RUNBOOK.md                 Operations guide (deploy, verify, troubleshoot)
```

## Prerequisites

- **Rancher Desktop** (or any local Kubernetes) with Kubernetes enabled
- **Helm 3**, **kubectl**, **Docker**
- Platform workspace sibling to this repo (`food-delivery-platform/` with all `food-*-service` folders)

## Quick start (Phase 5)

```bash
# From food-platform-deploy/
kubectl config use-context rancher-desktop   # if using Rancher Desktop

./scripts/local-deploy.sh
```

This builds all 7 Docker images, runs `helm dependency build`, and installs the platform into namespace `food-platform`.

### Individual scripts

```bash
# Build images only (uses ../scripts/docker-build-all.sh when present)
./scripts/local-build-images.sh

# Deploy without rebuilding images
./scripts/local-deploy.sh --skip-build

# Remove release (keeps namespace)
./scripts/local-teardown.sh

# Full cleanup including Postgres PVCs and namespace
./scripts/local-teardown.sh --purge-data --delete-namespace
```

### Access gateway

**With ingress** (`values-local.yaml` enables Traefik ingress):

```text
http://localhost/swagger-ui.html
```

**Without ingress / fallback:**

```bash
kubectl port-forward -n food-platform svc/food-api-gateway 8090:8090
# http://localhost:8090/swagger-ui.html
```

## Validate chart (Phase 4)

```bash
cd charts/food-platform
helm dependency build
helm lint . -f values-local.yaml
helm template food-platform . -f values-local.yaml --namespace food-platform
```

## GCP deploy (Phase 7 — stub)

Edit placeholders in `charts/food-platform/values-gcp.yaml` (`REPLACE_GCP_PROJECT`, domain, secrets), then:

```bash
gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT_ID
helm upgrade --install food-platform ./charts/food-platform \
  -f ./charts/food-platform/values-gcp.yaml \
  --namespace food-platform --create-namespace \
  --set global.imageTag=<git-sha>
```

Images: `us-central1-docker.pkg.dev/<project>/food/<service>:<tag>` (or GHCR — see comments in values file).

## Verify deployment (Phase 8)

```bash
./scripts/verify-k8s-health.sh
./scripts/verify-k8s-health.sh --wait 120 --check-ingress
```

See [docs/RUNBOOK.md](docs/RUNBOOK.md) for deploy, teardown, upgrade, and troubleshooting.

## Environment

Copy `scripts/env.example` and export overrides, or set inline:

| Variable | Default | Purpose |
|----------|---------|---------|
| `PLATFORM_ROOT` | parent of deploy repo | Path to `food-delivery-platform` workspace |
| `IMAGE_TAG` | `local` | Docker image tag (matches Helm `global.imageTag`) |
| `IMAGE_REGISTRY` | `food` | Image prefix `food/identity`, etc. |
| `HELM_NAMESPACE` | `food-platform` | Kubernetes namespace |

## Related docs

Platform design and phases: `food-delivery-platform/docs/DEPLOYMENT.md`
