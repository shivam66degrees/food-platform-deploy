# food-platform-deploy

Helm deployment repo for the food delivery platform (CD only). Service code and Docker images live in the seven `food-*-service` polyrepos.

## Layout

```
charts/food-platform/          Umbrella chart
├── Chart.yaml
├── values.yaml                Shared defaults
├── values-local.yaml          Rancher Desktop / local K8s
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
```

## Prerequisites

- Kubernetes cluster (Rancher Desktop for local)
- Helm 3
- Docker images built locally: `make docker-build-all` in the platform workspace

## Render / validate (Phase 4)

```bash
cd charts/food-platform
helm dependency build
helm lint . -f values-local.yaml
helm template food-platform . -f values-local.yaml --namespace food-platform
```

## Install (after Phase 5 scripts; manual preview)

```bash
helm upgrade --install food-platform ./charts/food-platform \
  -f ./charts/food-platform/values-local.yaml \
  --namespace food-platform --create-namespace
```

Gateway ingress (local): `http://localhost` when `gateway.ingress.enabled=true` in `values-local.yaml`.

## Related docs

Platform design and phases: `food-delivery-platform/docs/DEPLOYMENT.md`
