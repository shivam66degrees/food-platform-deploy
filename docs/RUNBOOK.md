# Food Platform — Operations Runbook

Operational guide for the Helm-based Kubernetes deployment (`food-platform-deploy`).

Platform design and phase plan: `food-delivery-platform/docs/DEPLOYMENT.md`.

---

## 1. Prerequisites

| Tool | Purpose |
|------|---------|
| **kubectl** | Cluster access |
| **helm 3** | Install / upgrade release |
| **docker** | Local image builds (`local-build-images.sh`) |
| **Rancher Desktop** (local) | Kubernetes + Traefik ingress |

**Local full-stack deploy:** allocate **10+ GB RAM** to the Rancher Desktop VM.

---

## 2. Deploy

### Local (Rancher Desktop)

```bash
kubectl config use-context rancher-desktop
cd food-platform-deploy
./scripts/local-deploy.sh
```

Options: `--skip-build`, `--timeout 25m`, `--namespace food-platform`.

### GCP (stub)

Edit `charts/food-platform/values-gcp.yaml` placeholders, then:

```bash
gcloud container clusters get-credentials CLUSTER --region REGION --project PROJECT
helm upgrade --install food-platform ./charts/food-platform \
  -f ./charts/food-platform/values-gcp.yaml \
  --namespace food-platform --create-namespace \
  --set global.imageTag=<git-sha>
```

---

## 3. Verify health

### In-cluster (all 7 services)

```bash
./scripts/verify-k8s-health.sh
./scripts/verify-k8s-health.sh --wait 120          # retry until ready
./scripts/verify-k8s-health.sh --check-ingress     # + http://localhost/actuator/health
```

Checks `/actuator/health` on identity, catalog, order, delivery, payment, notification, and gateway via the gateway pod.

### Manual

```bash
kubectl get pods -n food-platform
curl -s http://localhost/actuator/health              # Traefik ingress (local)
curl -s http://localhost/swagger-ui.html -o /dev/null -w "%{http_code}\n"
```

---

## 4. Access

| Environment | Gateway URL |
|-------------|-------------|
| **Local ingress** | http://localhost/swagger-ui.html |
| **Port-forward** | `kubectl port-forward -n food-platform svc/food-api-gateway 8090:8090` → http://localhost:8090 |
| **GCP** | `https://api.<your-domain>` (from `values-gcp.yaml`) |

---

## 5. Teardown

```bash
./scripts/local-teardown.sh                           # uninstall release, keep namespace
./scripts/local-teardown.sh --purge-data --delete-namespace   # full cleanup + PVCs
```

---

## 6. Upgrade / rollback

```bash
# Re-deploy after chart or values change
./scripts/local-deploy.sh --skip-build

# Helm rollback
helm history food-platform -n food-platform
helm rollback food-platform <revision> -n food-platform
```

---

## 7. Troubleshooting

### Pods OOMKilled / not Ready

- **Symptom:** `OOMKilled`, `Progress deadline exceeded`
- **Fix:** Increase Rancher Desktop RAM (10 GB+); `values-local.yaml` sets JVM limits — adjust if needed
- **Check:** `kubectl describe pod -n food-platform <pod>`

### Kafka not ready

- **Check:** `kubectl logs -n food-platform deploy/kafka --tail=50`
- **Fix:** ensure infra subchart Kafka env matches docker-compose (INTERNAL listener)

### Gateway 503 on ingress

- **Check:** `kubectl get pods -n food-platform -l app.kubernetes.io/name=food-api-gateway`
- **Wait:** `./scripts/verify-k8s-health.sh --wait 300`

### View logs

```bash
kubectl logs -n food-platform deploy/food-identity-service --tail=100
kubectl logs -n food-platform deploy/kafka --tail=50
```

### Image pull errors (GCP)

- Configure `global.imagePullSecrets` in `values-gcp.yaml`
- Ensure Artifact Registry / GHCR credentials and `imagePullPolicy: Always`

---

## 8. Service map (in-cluster DNS)

| Service | Port | Health |
|---------|------|--------|
| food-identity-service | 8080 | `/actuator/health` |
| food-catalog-service | 8082 | `/actuator/health` |
| food-order-service | 8083 | `/actuator/health` |
| food-delivery-service | 8084 | `/actuator/health` |
| food-payment-service | 8085 | `/actuator/health` |
| food-notification-service | 8086 | `/actuator/health` |
| food-api-gateway | 8090 | `/actuator/health` |

---

## 9. Related scripts

| Script | Purpose |
|--------|---------|
| `local-build-images.sh` | Build `food/*:local` from platform workspace |
| `local-deploy.sh` | Build + Helm install |
| `local-teardown.sh` | Uninstall + optional cleanup |
| `verify-k8s-health.sh` | Actuator checks on all services |
