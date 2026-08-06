# ArgoCD Demo Environment

GitOps demo environment: EKS/AKS cluster with ArgoCD, Octopus Deploy integration, and sample applications demonstrating environment-per-folder promotion workflows.

**Cloud providers:** This repo supports both AWS (EKS) and Azure (AKS). Use `terraform-eks.tfvars.example` for EKS setup, `terraform.tfvars.example` for AKS setup. The same ArgoCD + Octopus integration layer works identically on either cloud.

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | EKS/AKS cluster via Terraform | ✅ Complete |
| 2 | ArgoCD installation and exposure | ✅ Complete |
| 3 | Cluster infrastructure via GitOps | ✅ Complete |
| 4 | Octopus Deploy integration (ArgoCD gateway) | ✅ Complete |
| 4b | Octopus Kubernetes agent deployment target | 🔄 In Progress |
| 5 | Demo applications | ⏳ Pending |

---

## Quickstart — New User Setup

Everything needed to go from zero to a running environment. The per-phase sections below have deeper detail; this covers the happy path.

### Prerequisites

| Tool | Install | Notes |
|------|---------|-------|
| Azure CLI | `brew install azure-cli` | Run `az login` after (AKS only) |
| AWS CLI | `brew install awscli` | Run `aws configure` after (EKS only) |
| Terraform ≥ 1.5 | `brew install terraform` | |
| ArgoCD CLI | `brew install argocd` | Needed for bootstrap |
| netcat (`nc`) | Pre-installed on macOS | Used by token generation |
| kubectl | Via Docker Desktop or `brew install kubectl` | |
| direnv | `brew install direnv` | Required — manages secrets and shell env |

After installing direnv, add the hook to your shell profile if you haven't already:

```bash
# zsh
echo 'eval "$(direnv hook zsh)"' >> ~/.zshrc && source ~/.zshrc
```

### Step 1 — Fork and update the repo URL

ArgoCD pulls manifests from GitHub directly, so it needs to point at a repo you control. Fork `creid-octopus/iac-octopus`, clone your fork, then update the repoURL in the root Application:

```bash
# argocd/argocd/apps/root-app.yaml — change this line:
repoURL: https://github.com/YOUR-ORG/YOUR-FORK
```

Do the same for any Application manifest that references `creid-octopus/iac-octopus` if you want to manage your own copy of the config. If you're just running the demo read-only, you can leave it pointing at the original repo.

### Step 2 — Configure the Terraform backend

Edit `argocd/terraform/providers.tf` and fill in your Azure storage account for Terraform state:

```hcl
backend "azurerm" {
  resource_group_name  = "your-tf-state-rg"
  storage_account_name = "yourstorageaccount"
  container_name       = "your-container"
  key                  = "argocd-demo.tfstate"
}
```

### Step 3 — Set up credentials with direnv

Secrets live in `.envrc`, not in `terraform.tfvars`. Variables prefixed `TF_VAR_` are picked up by Terraform automatically, keeping credentials out of any file you might accidentally commit.

```bash
cp argocd/.envrc.example argocd/.envrc
# Edit argocd/.envrc with your values
direnv allow argocd/
```

The values you need to fill in:

```bash
export ARGOCD_PASSWORD="your-argocd-password"          # pick anything — sets the ArgoCD admin password
export OCTOPUS_API_KEY="API-YOUR-KEY-HERE"             # Infrastructure → API Keys in your Octopus space

export TF_VAR_argocd_admin_password="your-argocd-password"   # same value as ARGOCD_PASSWORD
export TF_VAR_octopus_api_key="API-YOUR-KEY-HERE"             # same value as OCTOPUS_API_KEY
```

### Step 4 — Create terraform.tfvars

```bash
cp argocd/terraform/terraform.tfvars.example argocd/terraform/terraform.tfvars
```

`tfvars` holds configuration (not secrets — those are in `.envrc`). The only values you must fill in:

```hcl
# bcrypt hash of your ArgoCD password — generate with:
# python3 -c "import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt(10)).decode())"
argocd_admin_password_hash = "$2a$10$..."

# Your Octopus space name — must match exactly as it appears in the UI
octopus_space_name = "Your Space Name"

# Override these if you're not using creid.octopus.app / Spaces-1:
# octopus_api_url      = "https://yourinstance.octopus.app"
# octopus_grpc_url     = "yourinstance.octopus.app:8443"
# octopus_space_id     = "Spaces-XXXX"
# octopus_environments = "development,test,production"
```

### Step 5 — Apply

```bash
cd argocd/terraform
terraform init    # downloads all providers
terraform plan    # review what will be created
terraform apply   # ~10 min: cluster + ArgoCD + Octopus gateway + K8s agent
```

`terraform apply` is fully self-contained — no pre-configured kubectl context or cloud CLI required (`aws eks update-kubeconfig` for EKS, `az aks get-credentials` for AKS).

### Step 6 — Configure local tools

```bash
cd ..   # back to argocd/ directory so direnv picks up .envrc
./scripts/update-env.sh   # reads TF outputs → writes .env.local + merges kubeconfig
direnv reload              # picks up ARGOCD_SERVER from the freshly written .env.local
```

### Step 7 — Bootstrap ArgoCD

```bash
./scripts/bootstrap.sh    # connects ArgoCD to the repo, applies root Application
```

ArgoCD will sync `cluster-infra` and deploy all child apps (Grafana + demo apps). Watch progress:

```bash
argocd app list
```

### What you'll have

- EKS cluster in `us-east-2` (t3.medium, autoscaler min 2 / max 2) or AKS in `centralus` (Standard_B2s)
- ArgoCD at `https://<external-ip-or-url>` (self-signed cert — click through the browser warning)
- Grafana in `monitoring` namespace (`kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring`)
- Octopus ArgoCD Gateway connected to your space
- Octopus Kubernetes Agent registered as a deployment target (`creid-eks` or `creid-aks`)
- Demo applications: kustomize (dev + staging), helm, and raw YAML

### Gotchas

**ArgoCD self-signed cert** — Browsers will warn; click through. All CLI commands use `--insecure`.

**ArgoCD IP changes on every recreation** — After each fresh `terraform apply`, re-run `update-env.sh` and `direnv reload` before `bootstrap.sh`. The new IP lands in `.env.local` automatically.

**Octopus ArgoCD Instance requires manual deletion** — The gateway registers an "ArgoCD Instance" in Octopus that has no public delete API yet. `pre-destroy.sh` pauses and shows the URL — delete it from the UI before pressing Enter. The Kubernetes agent target, by contrast, is fully managed by Terraform.

**Octopus gRPC port is 8443, not 443** — 443 is the REST API and returns a JSON 401 to gRPC clients. The defaults in `variables.tf` are correct; only relevant if you override `octopus_grpc_url`.

### Teardown

```bash
# From argocd/ — ARGOCD_PASSWORD is already in env via direnv
./scripts/pre-destroy.sh                          # removes ArgoCD apps; pauses for manual Octopus step
cd terraform && terraform destroy                  # removes everything; auto-deletes K8s agent target
```

---

## Configuration Approach

### How Terraform manages the cluster

`terraform apply` is fully self-contained — it does not require a pre-configured local kubectl context or any prior cloud CLI run (`aws eks update-kubeconfig` for EKS, `az aks get-credentials` for AKS). Specifically:

- The **Helm and Kubernetes providers** connect to the cluster directly using credentials from the EKS module output (`cluster_endpoint` + `cluster_certificate_authority_data` + `aws eks get-token` exec auth), not from `~/.kube/config`.
- **Local-exec scripts** (ArgoCD token generation, LoadBalancer URL polling) receive a generated kubeconfig as an environment variable and write it to a temp kubeconfig file at runtime. No `--context` flags, no local setup required.
- The **ArgoCD LoadBalancer URL** is computed during apply by polling the Kubernetes service until AWS/Azure assigns it. `argocd_web_ui_url` is derived from this automatically — no need to set it manually unless overriding with a DNS name.

The only inputs Terraform needs from outside are credentials (API keys, passwords, cloud auth) — set via `terraform.tfvars` or `TF_VAR_*` environment variables in `.envrc`.

### What you need for local interaction

After `terraform apply`, run these three commands:

```bash
./argocd/scripts/update-env.sh   # reads TF outputs, updates .env.local, merges kubeconfig
direnv reload                     # loads ARGOCD_SERVER into shell
./argocd/scripts/bootstrap.sh    # connects ArgoCD to the repo, applies root Application
```

`update-env.sh` handles both the kubeconfig merge (`aws eks update-kubeconfig` or `az aks get-credentials`) and capturing the current ArgoCD URL into `.env.local`. Headlamp picks up the `argocd-demo` context automatically.

> **On recreation:** The ArgoCD URL changes each time — re-run `update-env.sh` and `direnv reload` before running `bootstrap.sh`.

---

## Phase 1 — EKS/AKS Foundation

### What this does

Provisions an EKS (AWS) or AKS (Azure) cluster via Terraform. No applications or tooling are installed in this phase — just the cluster itself.

**EKS decisions baked in:**
- Region: `us-east-2`
- Node size: `t3.medium` (2 vCPU, 8 GB) — upgrade to `m6i.large` if resource pressure is observed
- Autoscaler: min 2, max 2 nodes
- Networking: VPC + private/public subnets + NAT gateway + EKS VPC CNI
- IAM: EKS managed node group with AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, AmazonEC2ContainerRegistryReadOnly

**AKS decisions baked in:**
- Region: `centralus`
- Node size: `Standard_B2s` (2 vCPU, 4 GB) — upgrade to `Standard_D2s_v3` if resource pressure is observed
- Autoscaler: min 1, max 2 nodes
- Networking: kubenet (no VNet setup required)
- Identity: system-assigned managed identity (no service principal)

### Prerequisites

#### For EKS:
- AWS CLI installed and configured: `aws configure`
- Terraform >= 1.5 installed
- Terraform state storage account (shared Azure blob)

#### For AKS:
- Azure CLI installed and logged in: `az login`
- Terraform >= 1.5 installed
- Terraform state storage account filled in `terraform/providers.tf`

### Setup

**1. Fill in the backend config**

Edit `terraform/providers.tf` and replace the three `TODO` values with your storage account details:

```hcl
backend "azurerm" {
  resource_group_name  = "your-tf-state-rg"
  storage_account_name = "yourstorageaccount"
  container_name       = "your-container"
  key                  = "argocd-demo.tfstate"
}
```

If the container doesn't exist yet:

```bash
az storage container create --name <container> --account-name <account>
```

**2. Create your tfvars file**

For EKS:
```bash
cp terraform/terraform-eks.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars with your values
```

For AKS:
```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars if you want to override any defaults
```

**3. Initialise and apply**

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

### After apply

See [Configuration Approach → What you need for local interaction](#configuration-approach) above. Run `az aks get-credentials` to configure kubectl and Headlamp, then bootstrap ArgoCD.

Verify the cluster is up:

```bash
kubectl get nodes --context argocd-demo
```

### Teardown

See the [full teardown instructions](#teardown) below. For EKS, nodes are automatically terminated when the cluster is deleted — no manual node group cleanup needed. For AKS, the `MC_*` managed resource group is auto-cleaned.

---

## Phase 2 — ArgoCD Installation and Exposure

### What this does

Installs ArgoCD into the cluster via Helm, managed by Terraform. Exposes it as a LoadBalancer service with ArgoCD's default self-signed TLS — access the UI at `https://<external-ip-or-url>` (browser will warn about the self-signed cert; click through).

**Decisions baked in:**
- Helm chart: `argo/argo-cd` from `https://argoproj.github.io/argo-helm`
- Exposure: LoadBalancer service, HTTPS with self-signed cert
- Single replica (non-HA) — appropriate for B2s nodes
- Admin password: bcrypt hash in `terraform.tfvars`, never in committed files

### Setup

**1. Add your password hash to `terraform.tfvars`**

This is where your bcrypt-hashed password goes (not the plaintext):

```hcl
argocd_admin_password_hash = "$2a$10$your-hash-here"
```

**2. Re-initialise Terraform** (new providers were added)

```bash
cd argocd/terraform
terraform init
```

**3. Apply**

```bash
terraform plan
terraform apply
```

This adds: the `argocd` namespace and the ArgoCD Helm release. The LoadBalancer IP takes ~60 seconds after apply for Azure to assign.

### After apply — get the ArgoCD URL

The URL is now a proper Terraform output — no kubectl command needed:

```bash
terraform -chdir=argocd/terraform output argocd_server_url
```

```bash
# Open the UI (accept the self-signed cert warning)
open https://<url>

# Log in via CLI
argocd login <url> --username admin --insecure
```

> **EKS note:** On EKS the LoadBalancer URL is a DNS hostname (e.g. `abc123.us-east-2.elb.amazonaws.com`), not an IP address. The `argocd_server_url` output returns the hostname. On AKS it's a traditional IP.

---

## Phase 3 — Cluster Infrastructure via GitOps

### What this does

Bootstraps the App of Apps pattern: a single root Application (`cluster-infra`) watches `argocd/argocd/apps/cluster-infra/` in the repo and creates an ArgoCD Application for each manifest it finds. Currently deploys Grafana; add more tools by dropping Application manifests into that directory.

**Decisions baked in:**
- Root app: `cluster-infra` Application pointing at `argocd/argocd/apps/cluster-infra/`
- **kube-prometheus-stack**: Prometheus + Grafana + kube-state-metrics + node-exporter in one chart, pre-wired together
- Grafana service: ClusterIP (port-forward to access) — change `service.type` to `LoadBalancer` in `cluster-infra/kube-prometheus/values.yaml` for persistent external access
- No persistence on Prometheus or Grafana — keeps teardown clean; metrics history is lost on pod restart
- AlertManager disabled — no alerting config needed for a demo environment
- AKS control plane scrapers disabled (kubeScheduler, kubeControllerManager, kubeEtcd, kubeProxy) — AKS doesn't expose these endpoints. On EKS, these are available but disabled by default in the chart.

### Prerequisites

- Phase 2 complete (ArgoCD running, external IP known)
- ArgoCD CLI installed (`brew install argocd`)
- Changes pushed to `https://github.com/creid-octopus/iac-octopus` — ArgoCD pulls from the remote, not your local filesystem

### Setup

**1. Push current changes to GitHub**

```bash
git add .
git commit -m "feat: phase 3 cluster infrastructure"
git push
```

**2. Run the bootstrap script**

```bash
ARGOCD_SERVER=<external-ip> ARGOCD_PASSWORD=<admin-password> ./scripts/bootstrap.sh
```

**3. Watch ArgoCD sync**

```bash
argocd app list
argocd app get cluster-infra
```

The `cluster-infra` app will appear first, then Grafana will be created as a child application and synced.

### Accessing Grafana

Grafana runs as ClusterIP — use port-forward to access it:

```bash
kubectl port-forward svc/kube-prometheus-grafana 3000:80 -n monitoring --context argocd-demo
# then open http://localhost:3000 — login with admin/admin
```

Kubernetes cluster dashboards (nodes, pods, namespaces, resource usage) are pre-installed by the chart. No data source configuration required — Prometheus is already wired in.

To expose Grafana externally, change `grafana.service.type` to `LoadBalancer` in `cluster-infra/kube-prometheus/values.yaml` and push — ArgoCD will update the service automatically.

### When the repo goes private

Run once after adding repo credentials:

```bash
GITHUB_PAT=<your-pat> argocd repo add https://github.com/creid-octopus/iac-octopus \
  --username creid-octopus \
  --password "$GITHUB_PAT"
```

---

## Phase 4 — Octopus Deploy Integration

### What this does

Installs the **Octopus ArgoCD Gateway** in the cluster — an in-cluster agent that connects to Octopus Cloud via outbound HTTPS. No inbound firewall rules or public ArgoCD API required. ArgoCD Application manifests are annotated to map them to Octopus projects and environments.

Also updates the ArgoCD Helm release to add a dedicated `octopus` service account with the API key and RBAC permissions the gateway needs.

**Decisions baked in:**
- Gateway chart: `oci://registry-1.docker.io/octopusdeploy/octopus-argocd-gateway-chart` v1.23.0
- Gateway namespace: `octopus-argocd-gateway`
- Gateway name in Octopus: `argocd-demo`
- Space: `CReid - Sandbox` (`Spaces-1`)
- Environments: `Development`, `Test`, `Production`
- ArgoCD account for gateway: `octopus` (apiKey-only, scoped RBAC)
- ArgoCD insecure: `true` (self-signed cert on internal gRPC connection)

### Prerequisites

- Phase 2 and 3 complete
- `argocd` CLI installed (`brew install argocd`)
- `nc` (netcat) available — used by the token generation script

### Setup

**1. Add Phase 4 values**

Secrets go in `.envrc` (via `TF_VAR_*`), not in `terraform.tfvars`:

```bash
# argocd/.envrc — add these if not already present
export TF_VAR_argocd_admin_password="your-plaintext-password"
export TF_VAR_octopus_api_key="API-YOUR-KEY-HERE"
```

`argocd_web_ui_url` does not need to be set — it is computed automatically from the LoadBalancer IP during apply. All other Phase 4 variables have correct defaults in `variables.tf`.

**2. Re-init and apply**

```bash
cd argocd/terraform
terraform init   # picks up null and time providers
terraform plan
terraform apply
```

`terraform apply` will:
1. Update ArgoCD (Helm upgrade to add the `octopus` account)
2. Wait 30s for ArgoCD to restart
3. Run a local-exec script that port-forwards to ArgoCD, generates an API token for the `octopus` account, and stores it as a Kubernetes secret
4. Install the gateway Helm chart, which reads that secret and registers with Octopus Cloud

### Verifying the connection

```bash
# Watch gateway logs — should show successful registration with Octopus
terraform output get_gateway_logs
# (run the printed kubectl command)
```

In Octopus Deploy → `CReid - Sandbox` → Infrastructure → Deployment Targets, `argocd-demo` should appear as a connected target.

### gRPC URL note

Octopus Cloud exposes two endpoints on different ports — **8443 for gRPC** (used by the gateway) and **443 for the REST API**. Using 443 will result in a 401 with `application/json` content-type in the gateway logs, which is the REST API responding to a gRPC request. Always use 8443.

### ArgoCD CLI context note

The `argocd` CLI persists server contexts in `~/.config/argocd/config`. If `bootstrap.sh` was previously run with the external IP, that context remains as the active one. The token generation script explicitly passes `--server localhost:18080` and calls `argocd context localhost:18080` to avoid silently falling back to a stale external IP context.

---

## Phase 4b — Kubernetes Agent Deployment Target

### What this does

Installs the **Octopus Kubernetes Agent** (polling Tentacle) alongside the ArgoCD gateway. Where the gateway provides GitOps sync visibility, the Kubernetes agent enables Octopus to execute Kubernetes deployment steps directly on the cluster.

Unlike the ArgoCD gateway instance (which has no public delete API), the Kubernetes agent deployment target is **fully managed by Terraform** — `terraform destroy` removes it from Octopus automatically. No manual step required.

**How the automated registration works** (no wizard bearer token needed):

1. Terraform generates a tentacle certificate and polling subscription URI locally via the `octopusdeploy` provider
2. A deployment target is pre-registered in Octopus with the cert thumbprint and subscription URI
3. The Helm chart installs the agent with the same cert and URI
4. The agent connects to Octopus, which matches it to the pre-existing target

**Decisions baked in:**
- Agent chart: `oci://registry-1.docker.io/octopusdeploy/kubernetes-agent` `3.*.*`
- Namespace: `octopus-k8s-agent`
- Target name: `creid-eks`
- Target tags: `k8s-agent`
- Polling address: derived from `octopus_api_url` (`https://polling.creid.octopus.app`)

### Prerequisites

- Phase 4 complete (Octopus API key already configured in `terraform.tfvars`)
- `octopus_space_name` added to `terraform.tfvars` (the chart uses the name, not the space ID)

### Setup

**1. Add to `terraform.tfvars`**

```hcl
octopus_space_name = "Your Space Name"   # e.g. "CReid - Sandbox"
```

**2. Re-init and apply** (new provider requires init)

```bash
cd argocd/terraform
terraform init   # picks up OctopusDeployLabs/octopusdeploy provider
terraform plan
terraform apply
```

### Verifying the connection

```bash
# Watch agent logs — should show successful registration with Octopus
terraform output get_k8s_agent_logs
# (run the printed kubectl command)
```

In Octopus Deploy → Infrastructure → Deployment Targets, `creid-aks` should appear as a healthy Kubernetes agent target.

### Teardown note

`terraform destroy` removes the Octopus deployment target automatically via the provider. No manual step needed — this is the key difference from the ArgoCD gateway instance.

---

## Teardown

Run in this order to avoid orphaned Azure resources.

### Step 1 — pre-destroy

```bash
ARGOCD_SERVER=<ip> ARGOCD_PASSWORD=<password> ./scripts/pre-destroy.sh
```

This logs into ArgoCD, cascade-deletes the `cluster-infra` app (which removes Grafana and any other managed apps), waits 30s for Kubernetes to clean up, then removes the `argocd-demo` context from your local kubeconfig.

### Step 2 — terraform destroy

```bash
cd argocd/terraform
terraform destroy
```

This removes (in dependency order): the gateway Helm release, the ArgoCD Helm release, the EKS cluster + VPC + node group (or AKS cluster + resource group). Deleting the EKS cluster also terminates all managed nodes and releases the LoadBalancer. For AKS, deleting the cluster also deletes the managed node resource group (`MC_*`), which cleans up the LoadBalancer IP and any Azure Disks.

### Known manual step — Octopus ArgoCD Instance

The Octopus ArgoCD Instance (not the same as a deployment target machine) does not yet have a public API delete endpoint. The pre-destroy script will open the Octopus UI URL and pause — delete the `argocd-demo` instance from that page before pressing Enter to continue. This will be automatable once Octopus exposes the endpoint.

### Known teardown notes

- **ArgoCD LoadBalancer URL**: Released when the cluster is deleted (EKS: AWS ELB; AKS: Azure LoadBalancer). No manual cleanup needed.
- **Grafana disks**: Persistence is disabled, so no persistent disks are created.
- **VPC (EKS only)**: The VPC, subnets, route tables, and NAT gateway are all managed by Terraform and cleaned up on `terraform destroy`. If you cancel midway through destroy, the VPC remains — run `terraform destroy` again to clean up.
- **kubeconfig**: Cleaned by `pre-destroy.sh`. If you skip the script, clean up manually:
  ```bash
  kubectl config delete-context argocd-demo
  kubectl config delete-cluster argocd-demo
  kubectl config delete-user clusterUser_<rg>-<cluster>    # AKS
  # or
  kubectl config delete-user <cluster-name>               # EKS
  ```
- **Static Public IP**: Not applicable — we're using a dynamic address assigned by the LoadBalancer service, which is released with the cluster.

### Recreating after teardown

```bash
cd argocd/terraform && terraform apply

cd ..   # back to argocd/ so direnv is active
./scripts/update-env.sh   # writes new IP to .env.local + merges kubeconfig
direnv reload              # loads updated ARGOCD_SERVER
./scripts/bootstrap.sh    # re-bootstraps ArgoCD against the new cluster
```

`update-env.sh` reads the new LoadBalancer URL directly from Terraform outputs — no manual URL lookup needed.

---

## Directory Structure

```
argocd/
├── terraform/                  ← EKS/AKS infrastructure + Octopus integrations
├── argocd/
│   ├── install-values.yaml     ← ArgoCD Helm values (Octopus account, RBAC)
│   └── apps/
│       ├── root-app.yaml       ← Root Application (App of Apps entry point)
│       └── cluster-infra/      ← Child Application manifests (one file = one app)
│           ├── kube-prometheus.yaml
│           ├── demo-kustomize-dev.yaml
│           ├── demo-kustomize-staging.yaml
│           ├── demo-helm.yaml
│           └── demo-raw.yaml
├── cluster-infra/
│   └── kube-prometheus/        ← Helm values for kube-prometheus-stack
│       └── values.yaml
├── environments/               ← Demo app configs (one subdirectory per approach)
│   ├── kustomize/
│   │   ├── base/
│   │   └── overlays/
│   │       ├── dev/
│   │       └── staging/
│   ├── helm/                   ← Chart + values.yaml
│   └── raw/                    ← Plain Kubernetes manifests
└── scripts/                    ← Bootstrap, teardown, and env helpers
```
