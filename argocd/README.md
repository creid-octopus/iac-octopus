# ArgoCD Demo Environment

GitOps demo environment: AKS cluster with ArgoCD, Octopus Deploy integration, and sample applications demonstrating environment-per-folder promotion workflows.

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | AKS cluster via Terraform | ✅ Complete |
| 2 | ArgoCD installation and exposure | ✅ Complete |
| 3 | Cluster infrastructure via GitOps | ✅ Complete |
| 4 | Octopus Deploy integration | ✅ Complete |
| 5 | Demo applications | 🔄 In Progress |

---

## Configuration Approach

### How Terraform manages the cluster

`terraform apply` is fully self-contained — it does not require a pre-configured local kubectl context or any prior `az aks get-credentials` run. Specifically:

- The **Helm and Kubernetes providers** connect to AKS directly using credentials from the `azurerm_kubernetes_cluster` resource output, not from `~/.kube/config`.
- **Local-exec scripts** (ArgoCD token generation, LoadBalancer IP polling) receive `kube_config_raw` as an environment variable and write it to a temp kubeconfig file at runtime. No `--context` flags, no local setup required.
- The **ArgoCD LoadBalancer IP** is computed during apply by polling the Kubernetes service until Azure assigns it. `argocd_web_ui_url` is derived from this automatically — no need to set it manually unless overriding with a DNS name.

The only inputs Terraform needs from outside are credentials (API keys, passwords) — set via `terraform.tfvars` or `TF_VAR_*` environment variables in `.envrc`.

### What you need for local interaction

After `terraform apply`, run these three commands:

```bash
./argocd/scripts/update-env.sh   # reads TF outputs, updates .env.local, merges kubeconfig
direnv reload                     # loads ARGOCD_SERVER into shell
./argocd/scripts/bootstrap.sh    # connects ArgoCD to the repo, applies root Application
```

`update-env.sh` handles both the kubeconfig merge (`az aks get-credentials`) and capturing the current ArgoCD IP into `.env.local`. Headlamp picks up the `argocd-demo` context automatically.

> **On recreation:** The ArgoCD external IP changes each time — re-run `update-env.sh` and `direnv reload` before running `bootstrap.sh`.

---

## Phase 1 — AKS Foundation

### What this does

Provisions a resource group and AKS cluster in Azure via Terraform. No applications or tooling are installed in this phase — just the cluster itself.

**Decisions baked in:**
- Region: `centralus`
- Node size: `Standard_B2s` (2 vCPU, 4 GB) — upgrade to `Standard_D2s_v3` if resource pressure is observed
- Autoscaler: min 1, max 2 nodes
- Networking: kubenet (no VNet setup required)
- Identity: system-assigned managed identity (no service principal)

### Prerequisites

- Azure CLI installed and logged in: `az login`
- Terraform >= 1.5 installed
- Terraform state storage account details filled in `terraform/providers.tf`

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

### Cost management

Stop the cluster when not in use (saves node VM costs; ~5 min to restart):

```bash
az aks stop --resource-group rg-argocd-demo --name aks-argocd-demo
az aks start --resource-group rg-argocd-demo --name aks-argocd-demo
```

> **Note:** The static Public IP (added in Phase 2) continues to accrue at ~$0.005/hr even while the cluster is stopped. Release it if leaving idle for an extended period.

### Teardown

See the [full teardown instructions](#teardown) below.

---

## Phase 2 — ArgoCD Installation and Exposure

### What this does

Installs ArgoCD into the cluster via Helm, managed by Terraform. Exposes it as a LoadBalancer service with ArgoCD's default self-signed TLS — access the UI at `https://<external-ip>` (browser will warn about the self-signed cert; click through).

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

### After apply — get the ArgoCD IP and log in

The IP is now a proper Terraform output — no kubectl command needed:

```bash
terraform -chdir=argocd/terraform output argocd_server_ip
```

```bash
# Open the UI (accept the self-signed cert warning)
open https://<ip>

# Log in via CLI
argocd login <ip> --username admin --insecure
```

---

## Phase 3 — Cluster Infrastructure via GitOps

### What this does

Bootstraps the App of Apps pattern: a single root Application (`cluster-infra`) watches `argocd/argocd/apps/cluster-infra/` in the repo and creates an ArgoCD Application for each manifest it finds. Currently deploys Grafana; add more tools by dropping Application manifests into that directory.

**Decisions baked in:**
- Root app: `cluster-infra` Application pointing at `argocd/argocd/apps/cluster-infra/`
- Grafana: Helm chart from `grafana/grafana`, values from `argocd/cluster-infra/grafana/values.yaml`
- Grafana service: ClusterIP (port-forward to access) — change to LoadBalancer in `values.yaml` for persistent access
- No persistence on Grafana — keeps teardown clean

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
kubectl port-forward svc/grafana 3000:80 -n monitoring --context argocd-demo
# then open http://localhost:3000 — login with admin/admin
```

Or switch `service.type` to `LoadBalancer` in `cluster-infra/grafana/values.yaml` and push — ArgoCD will update the service automatically.

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
- Space: `CReid - Sandbox` (`Spaces-3705`)
- Environments: `Development`, `Test`, `Production`
- ArgoCD account for gateway: `octopus` (apiKey-only, scoped RBAC)
- ArgoCD insecure: `true` (self-signed cert on internal gRPC connection)

### Prerequisites

- Phase 2 and 3 complete
- `argocd` CLI installed (`brew install argocd`)
- `nc` (netcat) available — used by the token generation script

### Setup

**1. Add Phase 4 values to `terraform.tfvars`**

```hcl
argocd_admin_password = "your-plaintext-password"
argocd_web_ui_url     = "https://YOUR_EXTERNAL_IP"
argocd_insecure       = true
octopus_api_key       = "API-YOUR-KEY-HERE"
```

The other Phase 4 variables have correct defaults in `variables.tf` — only override if needed.

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

This removes (in dependency order): the gateway Helm release, the ArgoCD Helm release, the AKS cluster, and the resource group. Deleting the AKS cluster also deletes the managed node resource group (`MC_*`), which cleans up the ArgoCD LoadBalancer IP and any Azure Disks.

### Known manual step — Octopus ArgoCD Instance

The Octopus ArgoCD Instance (not the same as a deployment target machine) does not yet have a public API delete endpoint. The pre-destroy script will open the Octopus UI URL and pause — delete the `argocd-demo` instance from that page before pressing Enter to continue. This will be automatable once Octopus exposes the endpoint.

### Known teardown notes

- **ArgoCD LoadBalancer IP**: Released when the AKS cluster is deleted (it lives in the `MC_` resource group). No manual cleanup needed.
- **Grafana disks**: Persistence is disabled, so no Azure Disks are created.
- **kubeconfig**: Cleaned by `pre-destroy.sh`. If you skip the script, clean up manually:
  ```bash
  kubectl config delete-context argocd-demo
  kubectl config delete-cluster argocd-demo
  kubectl config delete-user clusterUser_rg-argocd-demo_aks-argocd-demo
  ```
- **Static Public IP**: Not applicable — we're using a dynamic IP assigned by the LoadBalancer service, which is released with the cluster.

### Recreating after teardown

```bash
cd argocd/terraform
terraform apply

# Reconfigure kubectl and Headlamp
az aks get-credentials --resource-group rg-argocd-demo --name aks-argocd-demo --context argocd-demo

# Bootstrap ArgoCD (note: the external IP will be different after recreation)
ARGOCD_SERVER=<new-ip> ARGOCD_PASSWORD=<password> ./scripts/bootstrap.sh
```

> The ArgoCD external IP changes on every recreation. Update `ARGOCD_SERVER` in your `.envrc` after each recreate.

---

## Directory Structure

```
argocd/
├── terraform/          ← Phase 1: AKS infrastructure
├── argocd/             ← Phase 2+: ArgoCD Helm values and Application manifests
├── cluster-infra/      ← Phase 3: Helm values for cluster tools
├── environments/       ← Phase 5: Demo app environment-per-folder structure
└── scripts/            ← Bootstrap and teardown helpers
```
