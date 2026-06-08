#!/usr/bin/env bash
# pre-destroy.sh — clean up GitOps-managed resources before terraform destroy
#
# Run this BEFORE 'terraform destroy'. It removes ArgoCD-managed applications
# so their Kubernetes resources are cleanly deleted. The AKS cluster deletion
# will then clean up everything remaining in the node resource group (MC_*),
# including the ArgoCD LoadBalancer IP and any Azure Disks.
#
# Usage:
#   ARGOCD_SERVER=<ip> ARGOCD_PASSWORD=<password> ./scripts/pre-destroy.sh

set -euo pipefail

ARGOCD_PASSWORD="${ARGOCD_PASSWORD:?Set ARGOCD_PASSWORD to the ArgoCD admin password}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Always derive the live IP from Terraform state — never trust a cached env var
echo ">>> Fetching current ArgoCD server IP from Terraform state..."
ARGOCD_SERVER=$(terraform -chdir="$SCRIPT_DIR/../terraform" output -raw argocd_server_ip 2>/dev/null)
if [ -z "$ARGOCD_SERVER" ]; then
  echo "ERROR: Could not retrieve argocd_server_ip from Terraform state." >&2
  echo "       Is the cluster up? Try: terraform -chdir=argocd/terraform output argocd_server_ip" >&2
  exit 1
fi
echo "    ArgoCD server: $ARGOCD_SERVER"
OCTOPUS_URL="${OCTOPUS_URL:?Set OCTOPUS_URL (e.g. https://demo.octopus.app)}"
OCTOPUS_API_KEY="${OCTOPUS_API_KEY:?Set OCTOPUS_API_KEY}"
OCTOPUS_SPACE_ID="${OCTOPUS_SPACE_ID:-Spaces-3705}"
GATEWAY_NAME="${GATEWAY_NAME:-argocd-demo}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-argocd-demo}"
RESOURCE_GROUP="${RESOURCE_GROUP:-rg-argocd-demo}"
CLUSTER_NAME="${CLUSTER_NAME:-aks-argocd-demo}"

echo ">>> Logging in to ArgoCD at $ARGOCD_SERVER"
argocd login "$ARGOCD_SERVER" \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure \
  --grpc-web

echo ">>> Deleting cluster-infra app (cascade — removes Grafana and all child apps)"
argocd app delete cluster-infra --cascade --yes 2>/dev/null || echo "    (cluster-infra not found — skipping)"

echo ">>> Waiting for child app resources to be removed (up to 2 min)..."
# Brief wait for Kubernetes resources to be deleted before AKS teardown
sleep 30

echo ">>> Deregistering gateway '$GATEWAY_NAME' from Octopus ($OCTOPUS_URL)"
MACHINE_ID=$(curl -sf \
  -H "X-Octopus-ApiKey: $OCTOPUS_API_KEY" \
  "$OCTOPUS_URL/api/$OCTOPUS_SPACE_ID/machines?name=$GATEWAY_NAME" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Items'][0]['Id'] if d['Items'] else '')" 2>/dev/null || echo "")

if [ -n "$MACHINE_ID" ]; then
  curl -sf -X DELETE \
    -H "X-Octopus-ApiKey: $OCTOPUS_API_KEY" \
    "$OCTOPUS_URL/api/$OCTOPUS_SPACE_ID/machines/$MACHINE_ID" > /dev/null
  echo "    Removed deployment target $MACHINE_ID ($GATEWAY_NAME)"
else
  echo "    Gateway '$GATEWAY_NAME' not found in Octopus — skipping"
fi

echo ">>> Removing argocd-demo context from local kubeconfig"
kubectl config delete-context "$KUBECTL_CONTEXT" 2>/dev/null || true
kubectl config delete-cluster "$KUBECTL_CONTEXT" 2>/dev/null || true
kubectl config delete-user "clusterUser_${RESOURCE_GROUP}_${CLUSTER_NAME}" 2>/dev/null || true

echo ""
echo "✓ Pre-destroy complete. You can now run:"
echo "    cd argocd/terraform && terraform destroy"
echo ""
echo "  After terraform destroy, to recreate:"
echo "    terraform apply"
echo "    az aks get-credentials --resource-group $RESOURCE_GROUP --name $CLUSTER_NAME --context $KUBECTL_CONTEXT"
echo "    ARGOCD_SERVER=<new-ip> ARGOCD_PASSWORD=<password> ./scripts/bootstrap.sh"
