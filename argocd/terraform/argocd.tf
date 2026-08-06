resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
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

  timeout = 600 # ArgoCD can take a few minutes to fully start on small nodes
}

# Brief pause after ArgoCD Helm upgrade before the token generation script runs.
# The rollout-status check in the local-exec handles readiness, but this gives
# the API server a moment to initialize after the pod restarts.
resource "time_sleep" "wait_for_argocd" {
  depends_on      = [helm_release.argocd]
  create_duration = "30s"
}

# Poll until the ArgoCD LoadBalancer URL is assigned by AWS.
# Uses an external data source so the result is computed at apply time and
# flows through Terraform state — no temp files, works on any runner.
data "external" "argocd_lb_url" {
  depends_on = [time_sleep.wait_for_argocd]

  program = ["bash", "${path.module}/../scripts/get-argocd-lb-url.sh"]

  query = {
    kubeconfig = local.eks_kubeconfig
  }
}

locals {
  argocd_external_url = data.external.argocd_lb_url.result.url
  # Use override if set, otherwise compute from the live LoadBalancer URL
  argocd_web_ui_url   = var.argocd_web_ui_url != "" ? var.argocd_web_ui_url : (local.argocd_external_url != "" ? "https://${local.argocd_external_url}" : "")
}
