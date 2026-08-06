#!/usr/bin/env bash
# get-argocd-lb-url.sh — poll for the ArgoCD LoadBalancer URL and return it as JSON
#
# Called by the Terraform external data source in argocd.tf.
# Reads a JSON query from stdin containing the cluster kubeconfig,
# polls kubectl until the LoadBalancer URL is assigned, then writes
# {"url": "<dns-name>"} to stdout.
#
# On EKS, the AWS Load Balancer Controller creates an ALB/NLB with a DNS hostname
# (e.g., abc123.us-east-2.elb.amazonaws.com), not an IP address.
#
# Terraform external data source contract:
#   - stdin:  JSON object (the query map from the data source)
#   - stdout: JSON object (the result map returned to Terraform)
#   - stderr: free-form, shown in Terraform output on error
#   - exit 0: success; non-zero: error

set -euo pipefail

# Read query from stdin
query=$(cat)
kubeconfig=$(echo "$query" | jq -r '.kubeconfig')

# Write kubeconfig to a temp file — self-contained, no local context needed
KUBECONFIG_FILE=$(mktemp)
echo "$kubeconfig" > "$KUBECONFIG_FILE"
export KUBECONFIG="$KUBECONFIG_FILE"
trap 'rm -f "$KUBECONFIG_FILE"' EXIT

# Poll until the LoadBalancer URL is assigned by AWS (up to 5 min)
for i in $(seq 1 30); do
  # Try hostname first (ALB/NLB style), fall back to IP (Classic LB style)
  URL=$(kubectl get svc argocd-server -n argocd \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -z "$URL" ]; then
    # Fallback: some LB configurations return an IP instead of hostname
    URL=$(kubectl get svc argocd-server -n argocd \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  fi
  if [ -n "$URL" ]; then
    echo "{\"url\": \"$URL\"}"
    exit 0
  fi
  echo "Attempt $i/30 — waiting 10s for ArgoCD LoadBalancer URL..." >&2
  sleep 10
done

echo "ERROR: Timed out waiting for ArgoCD LoadBalancer URL" >&2
exit 1
