locals {
  # Internal gRPC address of the ArgoCD server — used by the gateway within the cluster
  argocd_grpc_url          = "${helm_release.argocd.name}-server.${kubernetes_namespace.argocd.metadata[0].name}.svc.cluster.local:443"
  argocd_token_secret_name = "argocd-gateway-token"
}

resource "kubernetes_namespace" "gateway" {
  metadata {
    name = var.gateway_namespace
  }
  depends_on = [azurerm_kubernetes_cluster.main]
}

# Octopus API key stored as a Kubernetes secret — never passed as a plain Helm value
resource "kubernetes_secret" "octopus_api_key" {
  metadata {
    name      = "octopus-server-access-token"
    namespace = kubernetes_namespace.gateway.metadata[0].name
  }
  data = {
    OCTOPUS_SERVER_ACCESS_TOKEN = var.octopus_api_key
  }
  type = "Opaque"
}

# Generates an ArgoCD API token for the dedicated 'octopus' account and stores it
# in a Kubernetes secret for the gateway to mount. Runs locally using kubectl + argocd CLI.
#
# Prerequisites on the machine running terraform apply:
#   - kubectl (with argocd-demo context configured via az aks get-credentials)
#   - argocd CLI (brew install argocd)
resource "null_resource" "argocd_token" {
  depends_on = [
    time_sleep.wait_for_argocd,
    kubernetes_namespace.gateway,
  ]

  triggers = {
    # Re-run if ArgoCD is reinstalled or the gateway namespace changes
    argocd_release_id = helm_release.argocd.id
    gateway_namespace = var.gateway_namespace
  }

  provisioner "local-exec" {
    # Kubeconfig is passed directly from TF state — no local 'az aks get-credentials' required.
    environment = {
      KUBECONFIG_CONTENT = azurerm_kubernetes_cluster.main.kube_config_raw
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      ARGOCD_NS="argocd"
      GATEWAY_NS="${var.gateway_namespace}"
      SECRET_NAME="${local.argocd_token_secret_name}"
      ARGOCD_PASSWORD="${var.argocd_admin_password}"

      # Write kubeconfig to a temp file — self-contained, no local context needed
      KUBECONFIG_FILE=$(mktemp)
      echo "$KUBECONFIG_CONTENT" > "$KUBECONFIG_FILE"
      export KUBECONFIG="$KUBECONFIG_FILE"
      trap 'rm -f "$KUBECONFIG_FILE"; kill "$PF_PID" 2>/dev/null || true' EXIT

      echo ">>> Waiting for argocd-server deployment to be ready..."
      kubectl rollout status deployment/argocd-server \
        --namespace "$ARGOCD_NS" \
        --timeout=300s

      echo ">>> Starting port-forward on localhost:18080 -> argocd-server:443..."
      kubectl port-forward svc/argocd-server \
        --namespace "$ARGOCD_NS" \
        18080:443 &
      PF_PID=$!

      echo ">>> Waiting for port-forward to become available..."
      for i in $(seq 1 20); do
        if nc -z localhost 18080 2>/dev/null; then
          echo "    Ready after $i attempt(s)."
          break
        fi
        echo "    Attempt $i/20 — retrying in 3s..."
        sleep 3
      done

      echo ">>> Logging in to ArgoCD..."
      argocd login localhost:18080 \
        --username admin \
        --password "$ARGOCD_PASSWORD" \
        --insecure \
        --grpc-web
      argocd context localhost:18080

      echo ">>> Generating API token for the octopus account..."
      ARGOCD_TOKEN=$(argocd account generate-token \
        --account octopus \
        --server localhost:18080 \
        --insecure \
        --grpc-web)

      echo ">>> Storing token in Kubernetes secret '$SECRET_NAME' (namespace: $GATEWAY_NS)..."
      kubectl create secret generic "$SECRET_NAME" \
        --namespace "$GATEWAY_NS" \
        --from-literal=ARGOCD_AUTH_TOKEN="$ARGOCD_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -

      echo ">>> Done. ArgoCD API token stored."
    EOT
  }
}

# Octopus ArgoCD Gateway — connects ArgoCD to Octopus Cloud via an in-cluster agent
resource "helm_release" "gateway" {
  name       = "octopus-argocd-gateway"
  repository = null
  chart      = "oci://registry-1.docker.io/octopusdeploy/octopus-argocd-gateway-chart"
  version    = var.gateway_chart_version
  namespace  = kubernetes_namespace.gateway.metadata[0].name

  depends_on = [
    null_resource.argocd_token,
    kubernetes_secret.octopus_api_key,
  ]

  values = [
    yamlencode({
      gateway = {
        argocd = {
          serverGrpcUrl                 = local.argocd_grpc_url
          insecure                      = var.argocd_insecure
          authenticationTokenSecretName = local.argocd_token_secret_name
          authenticationTokenSecretKey  = "ARGOCD_AUTH_TOKEN"
        }
        octopus = {
          serverGrpcUrl = var.octopus_grpc_url
          plaintext     = var.octopus_grpc_plaintext
        }
      }
      registration = {
        octopus = {
          name                        = var.gateway_name
          serverApiUrl                = var.octopus_api_url
          spaceId                     = var.octopus_space_id
          environments                = var.octopus_environments
          serverAccessTokenSecretName = kubernetes_secret.octopus_api_key.metadata[0].name
          serverAccessTokenSecretKey  = "OCTOPUS_SERVER_ACCESS_TOKEN"
        }
        argocd = {
          webUiUrl = local.argocd_web_ui_url
        }
      }
    })
  ]

  timeout = 300
  wait    = true
}
