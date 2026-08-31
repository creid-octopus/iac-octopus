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

  # Pin to a specific version. Update manually (or via Renovate PR) and validate
  # against the ArgoCD release notes before applying.
  version = "10.4.2"

  values = [file("${path.module}/../argocd/install-values.yaml")]

  # Admin password hash passed as sensitive — never written to the values file
  set_sensitive {
    name  = "configs.secret.argocdServerAdminPassword"
    value = var.argocd_admin_password_hash
  }

  timeout = 600 # ArgoCD can take a few minutes to fully start on B2s nodes
}

# ArgoCD config map — Repository controller config + Octopus API account.
#
# We apply this as a kubernetes_config_map instead of a helm_release set block
# because Helm's set YAML-quotes string values, breaking ArgoCD's config parser.
#
# The install-values.yaml has an empty configs.cm{} which would normally produce
# an empty argocd-cm; this manifest writes the real data. Applied after the
# helm_release (via depends_on) so it overrides any default.
resource "kubernetes_config_map" "argocd_cm" {
  metadata {
    name      = "argocd-cm"
    namespace = kubernetes_namespace.argocd.metadata[0].name
  }

  data = {
    accounts.octopus = "apiKey,renewAccessToken"
    repositories     = "- name: datadog\n  type: helm\n  url: https://helm.datadoghq.com\n  insecure: true\n"
  }

  depends_on = [helm_release.argocd]
}

# Brief pause after ArgoCD Helm upgrade before the token generation script runs.
# The rollout-status check in the local-exec handles readiness, but this gives
# the API server a moment to initialize after the pod restarts.
resource "time_sleep" "wait_for_argocd" {
  depends_on      = [helm_release.argocd]
  create_duration = "30s"
}

# Poll until the ArgoCD LoadBalancer IP is assigned by Azure.
# Uses an external data source so the result is computed at apply time and
# flows through Terraform state — no temp files, works on any runner.
data "external" "argocd_ip" {
  depends_on = [time_sleep.wait_for_argocd]

  program = ["bash", "${path.module}/../scripts/get-argocd-ip.sh"]

  query = {
    kubeconfig = azurerm_kubernetes_cluster.main.kube_config_raw
  }
}

locals {
  argocd_external_ip = data.external.argocd_ip.result.ip
  # Use override if set, otherwise compute from the live LoadBalancer IP
  argocd_web_ui_url = var.argocd_web_ui_url != "" ? var.argocd_web_ui_url : (local.argocd_external_ip != "" ? "https://${local.argocd_external_ip}" : "")
}
