# ── ArgoCD Cluster Registrations (c02, c03) ──────────────────────────────────
# Registers extra AKS clusters with ArgoCD via Secrets in the argocd namespace.
# Uses kubernetes_manifest (kind: Secret) — the manifest is sent directly to the
# Kubernetes API without any extra encoding, unlike kubernetes_secret which
# double-encodes data fields.
#
# ArgoCD watches for Secrets labeled `argocd.argoproj.io/secret-type: cluster`
# and automatically imports them as registered targets.

resource "kubernetes_manifest" "argocd_cluster" {
  for_each = local.extra_clusters

  manifest = {
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = azurerm_kubernetes_cluster.extra[each.key].name
      namespace = "argocd"
      labels = {
        "argocd.argoproj.io/secret-type" = "cluster"
      }
    }
    data = {
      # Data fields are sent as-is to the Kubernetes API.
      # Pre-base64-encode with Terraform so the API receives the correct values.
      name   = base64encode(azurerm_kubernetes_cluster.extra[each.key].name)
      server = base64encode(azurerm_kubernetes_cluster.extra[each.key].kube_config[0].host)
      config = base64encode(jsonencode({
        tlsClientConfig = {
          insecure = false
          caData   = azurerm_kubernetes_cluster.extra[each.key].kube_config[0].cluster_ca_certificate
        }
      }))
    }
  }

  depends_on = [helm_release.argocd, time_sleep.wait_for_argocd]
}
