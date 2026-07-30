# Self-hosted runner — Rancher Desktop CD

Auto-deploy from service CI to **local Kubernetes** (Rancher Desktop) requires a GitHub Actions runner on your Mac. GitHub’s cloud runners cannot reach your `rancher-desktop` cluster.

---

## Architecture

```text
Service repo (GitHub cloud)
  push master → docker push ghcr.io/…/food/identity:latest
             → repository_dispatch ─────────────────────────┐
                                                             ▼
food-platform-deploy (CD workflow)
  validate     → ubuntu-latest (helm lint)
  deploy       → self-hosted runner on YOUR Mac
              → helm upgrade → Rancher Desktop (namespace food-platform)
              → http://localhost/swagger-ui.html
```

---

## 1. Prerequisites (your Mac)

| Requirement | Check |
|-------------|--------|
| Rancher Desktop Kubernetes **on** | `kubectl cluster-info` |
| Context `rancher-desktop` | `kubectl config use-context rancher-desktop` |
| **10+ GB RAM** for Rancher VM | Rancher Desktop → Preferences |
| `helm`, `kubectl` on PATH | Usually `~/.rd/bin/` |
| `food-platform-deploy` on GitHub | Remote repo with `.github/workflows/deploy.yaml` |

---

## 2. Install the runner

From `food-platform-deploy/`:

```bash
./scripts/setup-self-hosted-runner.sh \
  --repo YOUR_GITHUB_USER/food-platform-deploy \
  --install-service
```

Or manual steps:

1. GitHub → **food-platform-deploy** → **Settings** → **Actions** → **Runners** → **New self-hosted runner**
2. Follow macOS instructions (labels `self-hosted`, `macOS` are added automatically)
3. Start the runner — **do not re-run config if already registered**:

```bash
cd food-platform-deploy
./scripts/start-runner.sh
```

The CD workflow selects runners with: `[self-hosted, macOS]`.

**Already configured?** If you see *"runner is already configured"*, skip setup — just run `./scripts/start-runner.sh`.  
To re-register from scratch: `cd ~/actions-runner-food-platform && ./config.sh remove` (needs a fresh token), then run setup again.

---

## 3. GitHub variables & secrets

### On every service repo (or org-level — recommended)

Set once at **Organization → Settings → Actions → Variables** so all 7 services inherit:

| Variable | Value | Purpose |
|----------|-------|---------|
| `DEPLOY_REPO` | `YOUR_USER/food-platform-deploy` | CD target repo |
| `CD_DEPLOY_ENVIRONMENT` | `local-k8s` | Route deploy to self-hosted runner |

**Secret** (org or each service repo):

| Secret | Value |
|--------|--------|
| `DEPLOY_REPO_TOKEN` | Fine-grained or classic PAT with **`repo`** scope on `food-platform-deploy` |

Create PAT: GitHub → **Settings** → **Developer settings** → **Personal access tokens** → generate with access to the deploy repo.

### On food-platform-deploy (optional)

Only if GHCR packages are **private**:

| Secret | Purpose |
|--------|---------|
| `GHCR_PULL_USER` | GitHub username |
| `GHCR_PULL_TOKEN` | PAT with `read:packages` |

If packages are **public**, skip these — Rancher pulls images directly from GHCR.

---

## 4. Verify end-to-end

1. **Runner online:** food-platform-deploy → Settings → Actions → Runners → green idle
2. **Manual CD test:** Actions → **CD** → **Run workflow**
   - environment: `local-k8s`
   - image_tag: `latest`
3. **Auto CD test:** push any change to `master` in a service repo (after variables are set)
4. **Check cluster:**
   ```bash
   kubectl get pods -n food-platform
   curl -s http://localhost/actuator/health
   ```

---

## 5. Troubleshooting

| Issue | Fix |
|-------|-----|
| Deploy job queued forever | Runner not running — `cd ~/actions-runner-food-platform && ./run.sh` |
| `Expected rancher-desktop context` | `kubectl config use-context rancher-desktop` on runner machine |
| `ImagePullBackOff` on pods | Make GHCR public or set `GHCR_PULL_*` secrets |
| Trigger job skipped | Set `DEPLOY_REPO` variable on service repo |
| `Bad credentials` on dispatch | Regenerate `DEPLOY_REPO_TOKEN` PAT |

---

## 6. When you move to GKE

Change org variable:

```text
CD_DEPLOY_ENVIRONMENT=gke
```

Add deploy-repo secrets: `GCP_PROJECT_ID`, `GKE_CLUSTER`, `GKE_REGION`, `GCP_SA_KEY_JSON`.  
Deploy jobs then run on `ubuntu-latest` — no self-hosted runner required.

---

## Related

- [RUNBOOK.md](./RUNBOOK.md) — deploy, verify, teardown
- [../README.md](../README.md) — CD overview
- Platform [DEPLOYMENT.md](../../docs/DEPLOYMENT.md) — full CI/CD design
