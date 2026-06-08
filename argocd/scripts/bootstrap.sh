#!/usr/bin/env bash
# bootstrap.sh — connects ArgoCD to the repo and applies the root Application
# Run once after 'terraform apply' for Phase 2
#
# Usage:
#   ARGOCD_SERVER=<external-ip> ARGOCD_PASSWORD=<admin-password> ./scripts/bootstrap.sh

set -euo pipefail

ARGOCD_SERVER="${ARGOCD_SERVER:?Set ARGOCD_SERVER to the ArgoCD LoadBalancer IP}"
ARGOCD_PASSWORD="${ARGOCD_PASSWORD:?Set ARGOCD_PASSWORD to the ArgoCD admin password}"
KUBECTL_CONTEXT="${KUBECTL_CONTEXT:-argocd-demo}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Logging in to ArgoCD at $ARGOCD_SERVER"
argocd login "$ARGOCD_SERVER" \
  --username admin \
  --password "$ARGOCD_PASSWORD" \
  --insecure \
  --grpc-web

# Repo is currently public — no credentials needed
# When the repo moves to private, uncomment and run:
#
# GITHUB_PAT="${GITHUB_PAT:?Set GITHUB_PAT to a token with repo read scope}"
# echo "→ Adding private repo credentials"
# argocd repo add https://github.com/creid-octopus/iac-octopus \
#   --username creid-octopus \
#   --password "$GITHUB_PAT"

echo "→ Applying root Application (cluster-infra)"
kubectl apply \
  -f "$SCRIPT_DIR/../argocd/apps/root-app.yaml" \
  --context "$KUBECTL_CONTEXT"

echo ""
echo "✓ Bootstrap complete."
echo "  ArgoCD will now sync all Applications in argocd/argocd/apps/cluster-infra/"
echo ""
echo "  Watch sync progress:"
echo "    argocd app list"
echo "    argocd app get cluster-infra"
