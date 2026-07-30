#!/usr/bin/env bash
# Shared paths and defaults for local deploy scripts (Phase 5).
set -euo pipefail

resolve_platform_root() {
  local deploy_root="$1"
  local root="${PLATFORM_ROOT:-$(cd "$deploy_root/.." && pwd)}"
  if [[ ! -d "$root/food-identity-service" || ! -d "$root/food-api-gateway" ]]; then
    echo "ERROR: Platform workspace not found at: $root" >&2
    echo "       Set PLATFORM_ROOT to the folder containing food-*-service repos." >&2
    exit 1
  fi
  printf '%s' "$root"
}

require_command() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: Required command not found: $cmd" >&2
    exit 1
  fi
}

require_kube_context() {
  require_command kubectl
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "ERROR: Kubernetes cluster is not reachable (kubectl cluster-info failed)." >&2
    echo "       Start Rancher Desktop Kubernetes or set KUBECONFIG." >&2
    exit 1
  fi
  echo "==> Kubernetes context: $(kubectl config current-context 2>/dev/null || echo unknown)"
}

chart_dir() {
  local deploy_root="$1"
  printf '%s/charts/food-platform' "$deploy_root"
}
