#!/usr/bin/env bash
# Start an already-configured self-hosted runner (no re-registration).
set -euo pipefail

RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner-food-platform}"

if [[ ! -d "$RUNNER_DIR" || ! -f "$RUNNER_DIR/.runner" ]]; then
  echo "ERROR: Runner not configured at $RUNNER_DIR" >&2
  echo "Run: ./scripts/setup-self-hosted-runner.sh --repo OWNER/food-platform-deploy" >&2
  exit 1
fi

cd "$RUNNER_DIR"

if pgrep -f "Runner.Listener" >/dev/null 2>&1; then
  echo "==> Runner already running (PID $(pgrep -f 'Runner.Listener'))"
  exit 0
fi

REPO="$(python3 -c "import json; print(json.load(open('.runner'))['gitHubUrl'])" 2>/dev/null || echo unknown)"
echo "==> Starting runner for $REPO"
echo "    Directory: $RUNNER_DIR"
echo "    Logs: $RUNNER_DIR/_diag/Runner_*.log"
echo ""
echo "    Keep this terminal open, or install as service:"
echo "      cd $RUNNER_DIR && sudo ./svc.sh install && sudo ./svc.sh start"
echo ""

exec ./run.sh
