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
OCTOPUS_URL="${OCTOPUS_URL:-https://creid.octopus.app}"
OCTOPUS_SPACE_ID="${OCTOPUS_SPACE_ID:-Spaces-1}"
# These are environment-specific. Set ENVIRONMENT or override each var directly.
ENVIRONMENT="${ENVIRONMENT:-${TF_VAR_environment:?Set ENVIRONMENT or TF_VAR_environment to the target environment (e.g. development)}}"
GATEWAY_NAME="${GATEWAY_NAME:-argocd-demo-${ENVIRONMENT}}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-argocd-demo-${ENVIRONMENT}}"
RESOURCE_GROUP="${RESOURCE_GROUP:-creid-rg-${ENVIRONMENT}}"
CLUSTER_NAME="${CLUSTER_NAME:-creid-aks-${ENVIRONMENT}}"

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

echo ""
echo "⚠  Manual step required — Octopus ArgoCD instance removal"
echo "   The Octopus ArgoCD Instance API does not yet expose a public delete endpoint."
echo "   Before continuing, remove '$GATEWAY_NAME' manually:"
echo ""
echo "   $OCTOPUS_URL/app#/$OCTOPUS_SPACE_ID/infrastructure/argocdinstances"
echo ""
echo "   Delete the '$GATEWAY_NAME' instance from that page, then press Enter to continue."
read -r

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
