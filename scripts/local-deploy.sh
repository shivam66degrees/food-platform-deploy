#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$(chart_dir "$DEPLOY_ROOT")"
RELEASE="${HELM_RELEASE:-food-platform}"
NAMESPACE="${HELM_NAMESPACE:-food-platform}"
VALUES_FILE="${HELM_VALUES:-$CHART_DIR/values-local.yaml}"
TIMEOUT="${HELM_TIMEOUT:-15m}"
SKIP_BUILD=false
SKIP_DEPS=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --skip-build       Do not rebuild Docker images
  --skip-deps        Skip helm dependency build
  --release NAME     Helm release name (default: food-platform)
  --namespace NS     Kubernetes namespace (default: food-platform)
  --values FILE      Values file (default: charts/food-platform/values-local.yaml)
  --timeout DURATION Helm --wait timeout (default: 15m)
  -h, --help         Show this help

Environment:
  PLATFORM_ROOT, IMAGE_TAG, IMAGE_REGISTRY, HELM_RELEASE, HELM_NAMESPACE
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=true; shift ;;
    --skip-deps) SKIP_DEPS=true; shift ;;
    --release) RELEASE="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --values) VALUES_FILE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_command helm
require_command docker
require_kube_context

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "ERROR: Values file not found: $VALUES_FILE" >&2
  exit 1
fi

if [[ "$SKIP_BUILD" != true ]]; then
  bash "$SCRIPT_DIR/local-build-images.sh"
  echo ""
fi

if [[ "$SKIP_DEPS" != true ]]; then
  echo "==> Updating Helm chart dependencies"
  helm dependency build "$CHART_DIR"
  echo ""
fi

echo "==> Installing/upgrading Helm release '$RELEASE' in namespace '$NAMESPACE'"
DEPLOY_EXIT=0
helm upgrade --install "$RELEASE" "$CHART_DIR" \
  -f "$VALUES_FILE" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait \
  --timeout "$TIMEOUT" || DEPLOY_EXIT=$?

if [[ "${DEPLOY_EXIT:-0}" -eq 0 ]]; then
  echo ""
  bash "$SCRIPT_DIR/verify-k8s-health.sh" --namespace "$NAMESPACE" --check-ingress \
    --ingress-url "${INGRESS_URL:-http://localhost}" || true
fi

echo ""
echo "==> Workloads"
kubectl get pods,svc,ingress -n "$NAMESPACE"

echo ""
echo "==> Access gateway"
if kubectl get ingress -n "$NAMESPACE" food-api-gateway >/dev/null 2>&1; then
  echo "    Ingress: http://localhost/swagger-ui.html"
  echo "    (Requires Rancher Desktop Traefik.)"
else
  echo "    Port-forward:"
  echo "      kubectl port-forward -n $NAMESPACE svc/food-api-gateway 8090:8090"
  echo "    Then open: http://localhost:8090/swagger-ui.html"
fi

echo ""
echo "==> Health checks (via port-forward in another terminal if needed)"
echo "    curl -s http://localhost:8090/actuator/health"

exit "${DEPLOY_EXIT:-0}"
