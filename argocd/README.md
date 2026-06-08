# ArgoCD Demo Environment

GitOps demo environment: AKS cluster with ArgoCD, Octopus Deploy integration, and sample applications demonstrating environment-per-folder promotion workflows.

## Phase Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | AKS cluster via Terraform | ✅ Complete |
| 2 | ArgoCD installation and exposure | ✅ Complete |
| 3 | Cluster infrastructure via GitOps | 🔄 In Progress |
| 4 | Octopus Deploy integration | ⏳ Pending |
| 5 | Demo applications | ⏳ Pending |

See the [Implementation Plan](../../obsidian notes — link separately) for full context.

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

### After apply — configure kubectl and Headlamp

Terraform outputs the exact command to run:

```bash
terraform output get_credentials_command
```

This will print something like:

```bash
az aks get-credentials --resource-group rg-argocd-demo --name aks-argocd-demo --context argocd-demo
```

Run that command to merge the cluster into your local `~/.kube/config`. Headlamp will pick it up automatically under the `argocd-demo` context.

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

Phase 1 only — no pre-destroy steps needed yet (no Kubernetes-created Azure resources exist):

```bash
cd terraform
terraform destroy
```

Also clean up the local kubeconfig context:

```bash
kubectl config delete-context argocd-demo
kubectl config delete-cluster argocd-demo
kubectl config delete-user clusterUser_rg-argocd-demo_aks-argocd-demo
```

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

```bash
# Get the external IP
terraform output get_argocd_ip
# Run the printed kubectl command to retrieve it

# Open the UI
open https://<external-ip>
# Accept the self-signed cert warning

# Log in via CLI
argocd login <external-ip> --username admin --insecure
# Enter your plaintext password when prompted
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

## Directory Structure

```
argocd/
├── terraform/          ← Phase 1: AKS infrastructure
├── argocd/             ← Phase 2+: ArgoCD Helm values and Application manifests
├── cluster-infra/      ← Phase 3: Helm values for cluster tools
├── environments/       ← Phase 5: Demo app environment-per-folder structure
└── scripts/            ← Bootstrap and teardown helpers
```
