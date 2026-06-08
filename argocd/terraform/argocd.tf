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
