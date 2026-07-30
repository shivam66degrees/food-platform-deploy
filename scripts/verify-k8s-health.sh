#!/usr/bin/env bash
# Verify actuator health for all 7 platform services in Kubernetes (Phase 8).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

NAMESPACE="${HELM_NAMESPACE:-food-platform}"
GATEWAY_DEPLOY="${GATEWAY_DEPLOY:-food-api-gateway}"
WAIT_SECONDS=0
CHECK_INGRESS=false
INGRESS_URL="${INGRESS_URL:-http://localhost}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Checks /actuator/health on all 7 services inside the cluster (via gateway pod curl).
Optionally checks external ingress URL for the gateway.

Options:
  --wait SECONDS       Retry until all checks pass or timeout (default: 0 = single attempt)
  --namespace NS       Kubernetes namespace (default: food-platform)
  --check-ingress      Also curl gateway via ingress URL (default: http://localhost)
  --ingress-url URL    Ingress base URL (default: http://localhost)
  -h, --help           Show this help

Environment:
  HELM_NAMESPACE, INGRESS_URL
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --wait) WAIT_SECONDS="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --check-ingress) CHECK_INGRESS=true; shift ;;
    --ingress-url) INGRESS_URL="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_kube_context

if ! kubectl get deploy -n "$NAMESPACE" "$GATEWAY_DEPLOY" >/dev/null 2>&1; then
  echo "ERROR: Deployment $GATEWAY_DEPLOY not found in namespace $NAMESPACE" >&2
  exit 1
fi

GATEWAY_POD="$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/name=$GATEWAY_DEPLOY" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$GATEWAY_POD" ]]; then
  echo "ERROR: No running pod for $GATEWAY_DEPLOY in namespace $NAMESPACE" >&2
  exit 1
fi

# name|in-cluster URL (resolved from gateway pod)
CHECKS=(
  "identity|http://food-identity-service:8080/actuator/health"
  "catalog|http://food-catalog-service:8082/actuator/health"
  "order|http://food-order-service:8083/actuator/health"
  "delivery|http://food-delivery-service:8084/actuator/health"
  "payment|http://food-payment-service:8085/actuator/health"
  "notification|http://food-notification-service:8086/actuator/health"
  "gateway|http://127.0.0.1:8090/actuator/health"
)

check_in_cluster() {
  local name="$1"
  local url="$2"
  local body
  if body="$(kubectl exec -n "$NAMESPACE" "$GATEWAY_POD" -- curl -sf --connect-timeout 5 "$url" 2>/dev/null)"; then
    if [[ "$body" == *'"status":"UP"'* ]] || [[ "$body" == *'"status": "UP"'* ]]; then
      echo "  OK   $name (in-cluster) $url"
      return 0
    fi
    echo "  FAIL $name (in-cluster) unexpected body: $body"
    return 1
  fi
  echo "  FAIL $name (in-cluster) $url"
  return 1
}

check_ingress() {
  local url="${INGRESS_URL%/}/actuator/health"
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 "$url" 2>/dev/null || echo 000)"
  if [[ "$code" =~ ^[23] ]]; then
    echo "  OK   gateway-ingress ($code) $url"
    return 0
  fi
  echo "  FAIL gateway-ingress ($code) $url"
  return 1
}

deadline=$((SECONDS + WAIT_SECONDS))

while true; do
  failures=0
  echo "==> K8s health check (namespace=$NAMESPACE, via pod=$GATEWAY_POD)"
  for entry in "${CHECKS[@]}"; do
    name="${entry%%|*}"
    url="${entry#*|}"
    check_in_cluster "$name" "$url" || failures=$((failures + 1))
  done

  if [[ "$CHECK_INGRESS" == true ]]; then
    check_ingress || failures=$((failures + 1))
  fi

  if [[ "$failures" -eq 0 ]]; then
    echo "==> All health checks passed"
    exit 0
  fi

  if [[ "$WAIT_SECONDS" -eq 0 || "$SECONDS" -ge "$deadline" ]]; then
    echo "==> $failures check(s) failed"
    echo "    kubectl get pods -n $NAMESPACE"
    echo "    kubectl logs -n $NAMESPACE deploy/$GATEWAY_DEPLOY --tail=50"
    exit 1
  fi

  sleep 5
done
