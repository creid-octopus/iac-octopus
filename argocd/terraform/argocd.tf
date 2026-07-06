resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [azurerm_kubernetes_cluster.main]
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  # Pin this once you've validated the install — avoids unexpected upgrades
  # version = "x.x.x"

  values = [file("${path.module}/../argocd/install-values.yaml")]

  # Admin password hash passed as sensitive — never written to the values file
  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.argocd_admin_password_hash
  }

  timeout = 600 # ArgoCD can take a few minutes to fully start on B2s nodes
}

# Brief pause after ArgoCD Helm upgrade before the token generation script runs.
# The rollout-status check in the local-exec handles readiness, but this gives
# the API server a moment to initialize after the pod restarts.
resource "time_sleep" "wait_for_argocd" {
  depends_on      = [helm_release.argocd]
  create_duration = "30s"
}

# Poll until the ArgoCD LoadBalancer IP is assigned by Azure, then write it to
# a temp file so subsequent resources can read it without a data source race condition.
resource "null_resource" "wait_for_argocd_ip" {
  depends_on = [time_sleep.wait_for_argocd]

  triggers = {
    argocd_release_id = helm_release.argocd.id
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG_CONTENT = azurerm_kubernetes_cluster.main.kube_config_raw
      IP_FILE            = "${path.module}/argocd-server-ip.tmp"
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBECONFIG_FILE=$(mktemp)
      echo "$KUBECONFIG_CONTENT" > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT

      echo ">>> Waiting for ArgoCD LoadBalancer IP (up to 5 min)..."
      for i in $(seq 1 30); do
        IP=$(kubectl get svc argocd-server -n argocd \
          -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        if [ -n "$IP" ]; then
          echo "    Got IP: $IP"
          echo -n "$IP" > "$IP_FILE"
          exit 0
        fi
        echo "    Attempt $i/30 — waiting 10s..."
        sleep 10
      done
      echo "ERROR: Timed out waiting for ArgoCD LoadBalancer IP" >&2
      exit 1
    EOT
  }
}

locals {
  # Read IP from temp file if present (written by wait_for_argocd_ip on apply).
  # Falls back to empty string on destroy runs where the file doesn't exist.
  argocd_external_ip = fileexists("${path.module}/argocd-server-ip.tmp") ? trimspace(file("${path.module}/argocd-server-ip.tmp")) : ""
  # Use override if set, otherwise compute from the live LoadBalancer IP
  argocd_web_ui_url  = var.argocd_web_ui_url != "" ? var.argocd_web_ui_url : (local.argocd_external_ip != "" ? "https://${local.argocd_external_ip}" : "")
}
