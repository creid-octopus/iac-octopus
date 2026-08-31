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

# Registers the Datadog Helm chart repository with ArgoCD so that the
# datadog/datadog chart in the Application below can be resolved.
#
# The proper alternative is to enable the ArgoCD Repository controller
# (CRD-based declarative registration), which ships in ArgoCD 2.7+ but
# must be explicitly enabled in the argocd-cm ConfigMap.
# See: https://argo-cd.readthedocs.io/en/stable/operator-manual/repositories/
resource "null_resource" "register_datadog_helm_repo" {
  depends_on = [time_sleep.wait_for_argocd]

  triggers = {
    # Re-run if ArgoCD is reinstalled
    argocd_release_id = helm_release.argocd.id
  }

  provisioner "local-exec" {
    environment = {
      KUBECONFIG_CONTENT = azurerm_kubernetes_cluster.main.kube_config_raw
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      ARGOCD_NS="argocd"
      ARGOCD_PASSWORD="${var.argocd_admin_password}"

      KUBECONFIG_FILE=$(mktemp)
      echo "$KUBECONFIG_CONTENT" > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      trap 'rm -f "$KUBECONFIG_FILE"; kill "$PF_PID" 2>/dev/null || true' EXIT

      echo ">>> Waiting for argocd-server deployment to be ready..."
      kubectl rollout status deployment/argocd-server \
        --namespace "$ARGOCD_NS" \
        --timeout=300s

      echo ">>> Starting port-forward on localhost:18083 -> argocd-server:443..."
      kubectl port-forward svc/argocd-server \
        --namespace "$ARGOCD_NS" \
        18083:443 &
      PF_PID=$!

      echo ">>> Waiting for port-forward to become available..."
      for i in $(seq 1 20); do
        if nc -z localhost 18083 2>/dev/null; then
          echo "    Ready after $i attempt(s)."
          break
        fi
        echo "    Attempt $i/20 — retrying in 3s..."
        sleep 3
      done

      echo ">>> Logging in to ArgoCD..."
      argocd login localhost:18083 \
        --username admin \
        --password "$ARGOCD_PASSWORD" \
        --insecure \
        --grpc-web

      echo ">>> Registering Datadog Helm chart repository..."
      argocd repo add https://helm.datadoghq.com \
        --type helm \
        --name datadog \
        --insecure-skip-server-verification \
        --grpc-web
    EOT
  }
}

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

  field_manager {
    force_conflicts = true
  }
}

# Pre-destroy cleanup — clears finalizers on ArgoCD applications so they don't block
# namespace deletion. Without this, `kubectl delete ns argocd` hangs forever.
resource "null_resource" "argocd_cleanup" {
  triggers = {
    argocd_release_id = helm_release.argocd.id
  }

  provisioner "local-exec" {
    when    = destroy
    environment = {
      KUBECONFIG_CONTENT = azurerm_kubernetes_cluster.main.kube_config_raw
    }
    command = <<-EOT
      set -euo pipefail

      ARGOCD_NS="argocd"

      KUBECONFIG_FILE=$(mktemp)
      echo "$KUBECONFIG_CONTENT" > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      trap 'rm -f "$KUBECONFIG_FILE"' EXIT

      echo ">>> Clearing finalizers on ArgoCD applications..."
      for app in $(kubectl get applications -n "$ARGOCD_NS" -o jsonpath='{.items[*].metadata.name}'); do
        kubectl patch application "$app" -n "$ARGOCD_NS" -p '{"metadata":{"finalizers":null}}' --type=merge
      done

      echo ">>> Done."
    EOT
  }

  depends_on = [
    azurerm_kubernetes_cluster.main,
  ]
}

# Monitoring namespace — Terraform owns this so ArgoCD doesn't need CreateNamespace=true
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
