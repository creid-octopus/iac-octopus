# bootstrap.tf — applies the ArgoCD root Application via the kubernetes provider
#
# Also creates the monitoring namespace and Datadog API key secret so that the
# ArgoCD-managed Datadog Helm app can mount credentials without inline secrets.
#
# This replaces the manual bootstrap.sh script. The root Application (cluster-infra)
# is an ArgoCD CRD, so it can be applied directly via kubernetes_manifest without
# needing the argoproj-labs/argocd provider or a running ArgoCD API connection.
#
# Once applied, ArgoCD watches argocd/argocd/apps/cluster-infra/ in the repo and
# creates child Applications for every manifest it finds there — kube-prometheus,
# demo-raw, demo-helm, demo-kustomize, demo-sync-waves, etc.
#
# depends_on helm_release.argocd ensures the ArgoCD CRDs are installed before
# this manifest is applied.

resource "kubernetes_manifest" "base_argocd_apps" {
  depends_on = [time_sleep.wait_for_argocd]

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "cluster-infra"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/creid-octopus/iac-octopus"
        targetRevision = "HEAD"
        path           = "argocd/argocd/apps/cluster-infra"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          selfHeal = true
          prune    = true
        }
        syncOptions = [
          "PruneLast=true"
        ]
      }
    }
  }
}

# Monitoring namespace — owns the namespace so ArgoCD doesn't need CreateNamespace=true
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
  depends_on = [azurerm_kubernetes_cluster.main]
}

# Datadog API key stored as a Kubernetes secret — never passed as a plain Helm value.
# The Datadog Helm chart references it via apiKeyExistingSecret (set in values.yaml).
resource "kubernetes_secret" "datadog_api" {
  metadata {
    name      = "datadog-api-secret"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  data = {
    apikey = var.datadog_api_key
  }
  type = "Opaque"
  depends_on = [
    kubernetes_namespace.monitoring,
    azurerm_kubernetes_cluster.main,
  ]
}
