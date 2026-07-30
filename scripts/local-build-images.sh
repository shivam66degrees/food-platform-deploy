#!/usr/bin/env bash
# Build all 7 service Docker images from the platform workspace (Phase 5).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PLATFORM_ROOT="$(resolve_platform_root "$DEPLOY_ROOT")"
TAG="${IMAGE_TAG:-local}"
REGISTRY="${IMAGE_REGISTRY:-food}"

BUILD_SCRIPT="$PLATFORM_ROOT/scripts/docker-build-all.sh"
if [[ -x "$BUILD_SCRIPT" ]]; then
  echo "==> Using platform build script: $BUILD_SCRIPT"
  IMAGE_TAG="$TAG" IMAGE_REGISTRY="$REGISTRY" bash "$BUILD_SCRIPT"
else
  echo "==> Building images from $PLATFORM_ROOT (tag=${REGISTRY}/*:${TAG})"
  SERVICES=(
    identity:food-identity-service
    catalog:food-catalog-service
    order:food-order-service
    delivery:food-delivery-service
    payment:food-payment-service
    notification:food-notification-service
    gateway:food-api-gateway
  )
  for entry in "${SERVICES[@]}"; do
    name="${entry%%:*}"
    dir="${entry##*:}"
    image="${REGISTRY}/${name}:${TAG}"
    echo "    $image  <=  $dir"
    docker build -t "$image" "$PLATFORM_ROOT/$dir"
  done
fi

echo ""
echo "==> Images ready for Helm (global.imageTag=${TAG})"
docker images --format '  {{.Repository}}:{{.Tag}}' | grep "^  ${REGISTRY}/" | grep ":${TAG}$" || true
