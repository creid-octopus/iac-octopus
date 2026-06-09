# Octopus Deploy Pipeline Setup

## Layered testing approach

ArgoCD and Octopus are independent layers. Test each one before wiring up the next.

**Layer 1 — ArgoCD only (no Octopus)**

Edit a file directly in git and push. ArgoCD auto-syncs (automated sync is enabled on all demo Applications). Use this layer to confirm the manifests, overlays, and Helm chart are correct before touching Octopus.

```bash
# Edit the image tag manually
vim argocd/environments/raw/deployment.yaml

git commit -am "test: bump raw to v3.0" && git push

# Confirm sync
argocd app wait demo-raw --health --timeout 60
kubectl get pods -n demo-raw
```

Do this for each approach (`demo-raw`, `demo-kustomize`, `demo-helm`, `demo-sync-waves`) until all four are `Synced/Healthy`.

**Layer 2 — Octopus GitOps (Commit to Git → ArgoCD sync)**

Octopus creates a release, picks an image tag from the Docker Hub feed, and runs a "Commit to Git" step that writes the tag to the appropriate file. From ArgoCD's perspective this is identical to Layer 1 — someone committed a git change. Octopus adds release versioning, environment gating, and audit trail. The gateway reports the ArgoCD sync outcome back into the deployment task.

**Layer 3 — Octopus direct deploy (K8s agent)**

Octopus applies resources directly via the K8s agent, bypassing the GitOps loop. ArgoCD immediately shows `OutOfSync`. Use this to demonstrate the contrast between GitOps promotion and imperative deploy, and ArgoCD's self-healing when you trigger a manual sync.

---

## Prerequisites

Before running `terraform apply` against `octopus-setup.tf`:

1. Add GitHub credentials to `.envrc`:
   ```bash
   export TF_VAR_github_pat="ghp_YOUR-PAT-HERE"   # repo Contents: Write scope
   export TF_VAR_github_user="your-github-username"
   ```
   The PAT needs write access to `argocd/environments/` in the repo.

2. Run `direnv allow` to reload, then:
   ```bash
   cd argocd/terraform
   terraform apply -target=octopusdeploy_docker_container_registry.docker_hub \
                   -target=octopusdeploy_project.demo_app_raw \
                   -target=octopusdeploy_project.demo_app_kustomize \
                   -target=octopusdeploy_project.demo_app_helm
   ```
   This creates the Docker Hub feed, the three projects, and all project variables. The deployment process steps are added manually in the Octopus UI (below).

---

## Docker Hub External Feed

If you prefer to set up the feed via the UI instead of Terraform:

1. Octopus → Library → External Feeds → Add Feed
2. Feed type: **Docker Container Registry**
3. Name: `Docker Hub`
4. URL: `https://index.docker.io`
5. No credentials needed for public images
6. Test with: `kostiscodefresh/gitops-simple-app` — should show tags `v1.0`, `v2.0`, `v3.0`

---

## Project Variables (common to all three projects)

All projects use the same variable names. If you applied Terraform above these are already populated. Otherwise, add them via the Octopus UI (Project → Variables):

| Variable | Type | Example value | Notes |
|---|---|---|---|
| `GitHub.PAT` | Sensitive | `ghp_...` | repo Contents: Write scope |
| `GitHub.User` | String | `creid-octopus` | GitHub username |
| `GitHub.Repo` | String | `github.com/creid-octopus/iac-octopus` | No `https://` prefix |
| `GitHub.Branch` | String | `main` | Branch to push to |
| `Image.Tag` | String | `v2.0` | Default tag; overridden at release time |
| `Deploy.Approach` | String | `raw` / `kustomize-dev` / `helm` | Fixed per project |

---

## Demo App Raw — Deployment Process

### Step 1 (GitOps): Commit to Git step

> **Note:** The "Commit to Git" step is Early Access as of mid-2026. If it's unavailable or unstable in your instance, use the fallback below.

1. Add step → **Commit to Git**
2. Name: `GitOps — Promote image tag in git`
3. **Authentication**: select the Library Git Credential for this repo (create one at Library → Git Credentials if it doesn't exist — use username + PAT)
4. **Repository URL**: `https://github.com/creid-octopus/iac-octopus`
5. **Branch**: `main` (or `#{GitHub.Branch}` if you want it variable)
6. **Commit message summary**: `deploy(#{Deploy.Approach}): promote to #{Image.Tag}`
7. **Script** → Bash → paste the section of `scripts/promote.sh` between the `[COMMIT TO GIT BODY]` markers:

```bash
set -euo pipefail
REPO_PATH=$(get_octopusvariable "Octopus.Calamari.Git.RepositoryPath")
IMAGE_TAG="#{Image.Tag}"
APPROACH="#{Deploy.Approach}"

case "$APPROACH" in
  raw)
    FILE="$REPO_PATH/argocd/environments/raw/deployment.yaml"
    sed -i "s|kostiscodefresh/gitops-simple-app:.*|kostiscodefresh/gitops-simple-app:${IMAGE_TAG}|g" "$FILE"
    sed -i "/^        version: /s|version: .*$|version: ${IMAGE_TAG}|" "$FILE"
    ;;
  kustomize-dev)
    sed -i "s|newTag:.*|newTag: ${IMAGE_TAG}|" \
      "$REPO_PATH/argocd/environments/kustomize/overlays/dev/kustomization.yaml"
    ;;
  kustomize-staging)
    sed -i "s|newTag:.*|newTag: ${IMAGE_TAG}|" \
      "$REPO_PATH/argocd/environments/kustomize/overlays/staging/kustomization.yaml"
    ;;
  helm)
    sed -i "s|^  tag:.*|  tag: ${IMAGE_TAG}|" \
      "$REPO_PATH/argocd/environments/helm/values.yaml"
    ;;
  *)
    echo "ERROR: Unknown Deploy.Approach '${APPROACH}'. Valid: raw|kustomize-dev|kustomize-staging|helm" >&2
    exit 1 ;;
esac
echo "==> Updated $FILE to ${IMAGE_TAG}"
```

The `Deploy.Approach` variable is fixed per project (set to `raw` for this project). After the step runs, the git commit triggers ArgoCD's auto-sync.

**Fallback: plain "Run a Script" step**

If Commit to Git is unavailable, use a "Run a Script" step with the full `scripts/promote.sh` content. Add `GitHub.PAT` (Sensitive), `GitHub.User`, `GitHub.Repo`, and `GitHub.Branch` as project variables, and set `COMMIT_LOCALLY=true` as a variable or edit the script directly.

### Step 2 (Direct): Deploy Kubernetes YAML

1. Add step → **Deploy Kubernetes YAML**
2. Name: `Direct — Apply to K8s agent`
3. Target tags (roles): `k8s-agent`
4. YAML source: **Inline YAML**
5. Paste the contents of `steps/raw-deploy.yaml`
6. Namespace: `demo-raw`

Octopus substitutes `#{Image.Tag}` before applying. After this step runs, ArgoCD will show the Application as `OutOfSync` because the live state differs from git — this is intentional for the demo.

> **Demo tip:** Run the GitOps step, show ArgoCD syncing and returning to Synced. Then run the Direct step, show ArgoCD detecting drift and flipping to OutOfSync. Trigger a manual ArgoCD sync to show it self-healing back to the git state.

---

## Demo App Kustomize — Deployment Process

### Step 1 (GitOps): Commit to Git step

Same configuration as demo-app-raw, step 1. The `Deploy.Approach` variable is `kustomize-dev`, so the script updates `overlays/dev/kustomization.yaml` → `newTag`.

To demo staging promotion, change `Deploy.Approach` to `kustomize-staging` and redeploy (or create a separate environment-scoped variable set).

### Step 2 (Direct): Run kubectl with kustomize

1. Add step → **Run a Script** → Bash
2. Name: `Direct — kubectl apply -k (kustomize)`
3. Target tags (roles): `k8s-agent`
4. Script body:
   ```bash
   # Clone the repo to get the kustomize overlays
   WORK_DIR=$(mktemp -d)
   trap 'rm -rf "$WORK_DIR"' EXIT
   git clone --depth 1 https://#{GitHub.User}:#{GitHub.PAT}@#{GitHub.Repo} "$WORK_DIR/repo"
   cd "$WORK_DIR/repo"

   # Patch the image tag inline before applying
   cd argocd/environments/kustomize/overlays/dev
   kustomize edit set image docker.io/kostiscodefresh/gitops-simple-app:#{Image.Tag}
   kubectl apply -k .
   ```

> Note: `kubectl` and `kustomize` must be available on the K8s agent worker. The Kubernetes agent runs in-cluster, so `kubectl` applies directly without extra auth.

Alternatively, paste the expanded YAML from `steps/kustomize-deploy.yaml` into a **Deploy Kubernetes YAML** step — this avoids the kustomize dependency.

---

## Demo App Helm — Deployment Process

### Step 1 (GitOps): Commit to Git step

Same configuration as demo-app-raw, step 1. The `Deploy.Approach` variable is `helm`; the script updates `environments/helm/values.yaml` → `tag:`.

### Step 2 (Direct): Upgrade a Helm Chart

1. Add step → **Upgrade a Helm Chart**
2. Name: `Direct — Helm upgrade via K8s agent`
3. Target tags (roles): `k8s-agent`
4. Chart source: **Git Repository**
   - Repository URL: `https://github.com/creid-octopus/iac-octopus`
   - Username: `#{GitHub.User}`
   - Password: `#{GitHub.PAT}`
   - Chart path: `argocd/environments/helm`
5. Release name: `demo-app-helm`
6. Namespace: `demo-helm`
7. Additional values YAML: paste `steps/helm-values-override.yaml`:
   ```yaml
   image:
     tag: "#{Image.Tag}"
   ```

---

## Creating Releases

Releases in Octopus can either:
- **Use a fixed `Image.Tag`** — set the variable in the project, click Deploy.
- **Bind to the Docker Hub feed** — version the release by selecting an image tag from the feed.

To bind to the Docker Hub feed:
1. Project → Process → click the Git-update step → Package References → Add Reference
2. Feed: `Docker Hub`
3. Package ID: `kostiscodefresh/gitops-simple-app`
4. This makes the tag selectable when creating a release; use `#{Octopus.Action.Package[gitops-simple-app].PackageVersion}` as the `Image.Tag` value (or bind the variable to the package version in the variable editor).

---

## Sync Waves Demo

The `demo-sync-waves` Application in `argocd/argocd/apps/cluster-infra/demo-sync-waves.yaml` deploys resources from `environments/sync-waves/` in this order:

| File | Phase | Wave | Resource | What it shows |
|---|---|---|---|---|
| `00-presync-db-migrate.yaml` | PreSync | -1 | Job | Runs first, blocks Sync from starting until complete |
| `01-wave0-config.yaml` | Sync | 0 | Namespace + ConfigMap | Applied before the Deployment |
| `02-wave1-app.yaml` | Sync | 1 | Deployment + Service | Waits for wave 0 to be healthy |
| `03-postsync-smoke-test.yaml` | PostSync | — | Job | HTTP smoke test; failure marks sync as failed |

To demo this in ArgoCD: delete the Application and re-apply, then watch the resource tree in the ArgoCD UI — you'll see the PreSync Job run, then wave 0 resources appear, then wave 1, then the PostSync Job.

To contrast with Octopus: show a multi-step deployment process where steps mirror the same phases — a "Run a Script" step for pre-flight, a "Deploy Kubernetes YAML" step for the app, and a "Run a Script" step for post-deploy verification.
