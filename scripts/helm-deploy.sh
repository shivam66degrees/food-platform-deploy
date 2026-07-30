#!/usr/bin/env bash
# Helm install/upgrade without building images — used by CD and GHCR-based deploys.
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
SKIP_DEPS=false
SKIP_VERIFY=false
IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
IMAGE_TAG="${IMAGE_TAG:-}"
EXTRA_HELM_SET=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Helm upgrade --install with optional image registry/tag overrides (no docker build).

Options:
  --values FILE        Values file (default: charts/food-platform/values-local.yaml)
  --release NAME       Helm release (default: food-platform)
  --namespace NS       Namespace (default: food-platform)
  --timeout DURATION   Helm --wait timeout (default: 15m)
  --image-registry REG e.g. ghcr.io/myorg or us-central1-docker.pkg.dev/PROJECT/food
  --image-tag TAG      Pins global.imageTag (e.g. git SHA)
  --set key=val        Extra Helm --set (repeatable)
  --skip-deps          Skip helm dependency build
  --skip-verify        Skip post-deploy verify-k8s-health.sh
  -h, --help           Show this help

Environment:
  HELM_RELEASE, HELM_NAMESPACE, HELM_VALUES, HELM_TIMEOUT
  IMAGE_REGISTRY, IMAGE_TAG, INGRESS_URL

Examples:
  # Local cluster, images already built as food/*:local
  ./scripts/helm-deploy.sh --skip-verify

  # Pull from GHCR (after service CI pushed images)
  IMAGE_REGISTRY=ghcr.io/myorg IMAGE_TAG=\$GITHUB_SHA \\
    HELM_VALUES=charts/food-platform/values-cd-ghcr.yaml \\
    ./scripts/helm-deploy.sh --image-registry ghcr.io/myorg --image-tag \$GITHUB_SHA
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --values) VALUES_FILE="$2"; shift 2 ;;
    --release) RELEASE="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --image-registry) IMAGE_REGISTRY="$2"; shift 2 ;;
    --image-tag) IMAGE_TAG="$2"; shift 2 ;;
    --set) EXTRA_HELM_SET+=("$2"); shift 2 ;;
    --skip-deps) SKIP_DEPS=true; shift ;;
    --skip-verify) SKIP_VERIFY=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_command helm
require_kube_context

if [[ ! -f "$VALUES_FILE" ]]; then
  echo "ERROR: Values file not found: $VALUES_FILE" >&2
  exit 1
fi

HELM_SET_ARGS=()
if [[ -n "$IMAGE_REGISTRY" ]]; then
  HELM_SET_ARGS+=(--set "global.imageRegistry=$IMAGE_REGISTRY")
fi
if [[ -n "$IMAGE_TAG" ]]; then
  HELM_SET_ARGS+=(--set "global.imageTag=$IMAGE_TAG")
fi
for s in "${EXTRA_HELM_SET[@]+"${EXTRA_HELM_SET[@]}"}"; do
  HELM_SET_ARGS+=(--set "$s")
done

if [[ "$SKIP_DEPS" != true ]]; then
  echo "==> Updating Helm chart dependencies"
  helm dependency build "$CHART_DIR"
  echo ""
fi

echo "==> Helm upgrade --install '$RELEASE' (namespace=$NAMESPACE)"
echo "    values: $VALUES_FILE"
[[ -n "$IMAGE_REGISTRY" ]] && echo "    imageRegistry: $IMAGE_REGISTRY"
[[ -n "$IMAGE_TAG" ]] && echo "    imageTag: $IMAGE_TAG"

DEPLOY_EXIT=0
HELM_CMD=(helm upgrade --install "$RELEASE" "$CHART_DIR" -f "$VALUES_FILE")
if ((${#HELM_SET_ARGS[@]} > 0)); then
  HELM_CMD+=("${HELM_SET_ARGS[@]}")
fi
HELM_CMD+=(--namespace "$NAMESPACE" --create-namespace --wait --timeout "$TIMEOUT")
"${HELM_CMD[@]}" || DEPLOY_EXIT=$?

if [[ "${DEPLOY_EXIT:-0}" -eq 0 && "$SKIP_VERIFY" != true ]]; then
  echo ""
  bash "$SCRIPT_DIR/verify-k8s-health.sh" --namespace "$NAMESPACE" --check-ingress \
    --ingress-url "${INGRESS_URL:-http://localhost}" || true
fi

echo ""
echo "==> Workloads"
kubectl get pods,svc,ingress -n "$NAMESPACE" 2>/dev/null || true

exit "${DEPLOY_EXIT:-0}"
