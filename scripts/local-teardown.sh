#!/usr/bin/env bash
# Remove the platform Helm release from local Kubernetes (Phase 5).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

RELEASE="${HELM_RELEASE:-food-platform}"
NAMESPACE="${HELM_NAMESPACE:-food-platform}"
DELETE_NAMESPACE=false
PURGE_DATA=false

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --delete-namespace   Delete the whole namespace after uninstall
  --purge-data         Delete PVCs in the namespace (Postgres data)
  --release NAME       Helm release name (default: food-platform)
  --namespace NS       Kubernetes namespace (default: food-platform)
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete-namespace) DELETE_NAMESPACE=true; shift ;;
    --purge-data) PURGE_DATA=true; shift ;;
    --release) RELEASE="$2"; shift 2 ;;
    --namespace) NAMESPACE="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

require_command helm
require_kube_context

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "==> Uninstalling Helm release '$RELEASE' from namespace '$NAMESPACE'"
  helm uninstall "$RELEASE" -n "$NAMESPACE"
else
  echo "==> Release '$RELEASE' not found in namespace '$NAMESPACE' (nothing to uninstall)"
fi

if [[ "$PURGE_DATA" == true ]]; then
  echo "==> Deleting persistent volume claims in namespace '$NAMESPACE'"
  kubectl delete pvc --all -n "$NAMESPACE" --ignore-not-found
fi

if [[ "$DELETE_NAMESPACE" == true ]]; then
  echo "==> Deleting namespace '$NAMESPACE'"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=true
else
  echo "==> Namespace '$NAMESPACE' kept (use --delete-namespace to remove)"
fi

echo "==> Teardown complete"
