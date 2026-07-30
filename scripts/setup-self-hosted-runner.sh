#!/usr/bin/env bash
# Install and register a GitHub Actions self-hosted runner for Rancher Desktop CD.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner-food-platform}"
RUNNER_VERSION="${RUNNER_VERSION:-2.321.0}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,macOS}"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Registers a self-hosted runner on food-platform-deploy for local-k8s CD
(Rancher Desktop Kubernetes).

Prerequisites:
  - Rancher Desktop: Kubernetes enabled, context 'rancher-desktop'
  - helm, kubectl on PATH (Rancher Desktop installs these)
  - Registration token from GitHub (see below)

Options:
  --repo OWNER/REPO     GitHub repo (default: prompt or GITHUB_REPO env)
  --token TOKEN         One-time registration token (or prompt)
  --dir PATH            Install directory (default: ~/actions-runner-food-platform)
  --install-service     Install runner as a launchd service (starts on login)
  -h, --help            Show this help

Get a registration token:
  GitHub → food-platform-deploy → Settings → Actions → Runners → New self-hosted runner
  Copy the token from the configure command (valid ~1 hour).

Or with GitHub CLI (repo admin):
  gh api repos/OWNER/food-platform-deploy/actions/runners/registration-token -X POST \\
    --jq .token

After registration, set org/repo variables on all 7 service repos (see docs/SELF_HOSTED_RUNNER.md).
EOF
}

REPO="${GITHUB_REPO:-}"
TOKEN=""
INSTALL_SERVICE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    --token) TOKEN="$2"; shift 2 ;;
    --dir) RUNNER_DIR="$2"; shift 2 ;;
    --install-service) INSTALL_SERVICE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

echo "==> Checking prerequisites"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: Missing command: $1" >&2
    exit 1
  fi
}

require_cmd kubectl
require_cmd helm
require_cmd curl
require_cmd tar

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: Kubernetes not reachable. Start Rancher Desktop and enable Kubernetes." >&2
  exit 1
fi

CTX="$(kubectl config current-context 2>/dev/null || true)"
echo "    kubectl context: $CTX"
if [[ "$CTX" != "rancher-desktop" ]]; then
  echo "WARNING: Expected context 'rancher-desktop'. CD workflow will fail preflight unless context matches."
  echo "         Run: kubectl config use-context rancher-desktop"
fi

if [[ -z "$REPO" ]]; then
  read -r -p "GitHub repo (OWNER/food-platform-deploy): " REPO
fi
[[ -n "$REPO" ]] || { echo "ERROR: --repo required" >&2; exit 1; }

if [[ -z "$TOKEN" ]]; then
  echo ""
  echo "Open: https://github.com/$REPO/settings/actions/runners/new"
  echo "Select macOS → copy the registration token from the configure step."
  read -r -p "Registration token: " TOKEN
fi
[[ -n "$TOKEN" ]] || { echo "ERROR: --token required" >&2; exit 1; }

ARCH="$(uname -m)"
case "$ARCH" in
  arm64|aarch64) RUNNER_ARCH="arm64" ;;
  x86_64) RUNNER_ARCH="x64" ;;
  *) echo "ERROR: Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

RUNNER_TARBALL="actions-runner-osx-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TARBALL}"

echo ""
echo "==> Installing runner to $RUNNER_DIR"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -f ./config.sh ]]; then
  echo "    Downloading $RUNNER_URL"
  curl -fsSL -o "$RUNNER_TARBALL" "$RUNNER_URL"
  tar xzf "$RUNNER_TARBALL"
  rm -f "$RUNNER_TARBALL"
fi

if [[ -f ./.runner ]]; then
  echo ""
  echo "==> Runner already configured for: $(python3 -c "import json; print(json.load(open('.runner'))['gitHubUrl'])" 2>/dev/null || grep gitHubUrl .runner)"
  echo "    Skipping config.sh (to reconfigure: ./config.sh remove, then re-run this script)"
  echo ""
  if pgrep -f "Runner.Listener" >/dev/null 2>&1; then
    echo "    Runner process is already running."
  else
    echo "    Start the runner:"
    echo "      cd $RUNNER_DIR && ./run.sh"
    echo "    Or install as background service (requires sudo):"
    echo "      cd $RUNNER_DIR && sudo ./svc.sh install && sudo ./svc.sh start"
  fi
else
  echo ""
  echo "==> Configuring runner (labels: $RUNNER_LABELS)"
  ./config.sh \
    --url "https://github.com/$REPO" \
    --token "$TOKEN" \
    --name "rancher-mac-$(hostname -s)" \
    --labels "$RUNNER_LABELS" \
    --unattended \
    --replace
fi

echo ""
if [[ "$INSTALL_SERVICE" == true ]]; then
  echo "==> Installing launchd service (starts on login)"
  sudo ./svc.sh install
  sudo ./svc.sh start
  echo "    Status: ./svc.sh status"
else
  echo "==> Runner configured. Start manually:"
  echo "    cd $RUNNER_DIR && ./run.sh"
  echo ""
  echo "    Or install as service:"
  echo "    cd $RUNNER_DIR && sudo ./svc.sh install && sudo ./svc.sh start"
fi

echo ""
echo "==> Next: GitHub variables (org or each service repo)"
cat <<EOF

  DEPLOY_REPO=$REPO
  CD_DEPLOY_ENVIRONMENT=local-k8s

Secret on each service repo:
  DEPLOY_REPO_TOKEN=<PAT with repo scope on food-platform-deploy>

Optional on food-platform-deploy (private GHCR):
  GHCR_PULL_USER=<github-user>
  GHCR_PULL_TOKEN=<PAT with read:packages>

Full guide: $DEPLOY_ROOT/docs/SELF_HOSTED_RUNNER.md
EOF
