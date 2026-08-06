locals {
  # Environment-suffixed resource names — all resources include the environment
  # so multiple environments (development, test, production) can coexist independently.
  env          = var.environment
  cluster_name = "${var.cluster_name}-${local.env}"

  # ─── Cloud-agnostic cluster reference ────────────────────────────────────
  # EKS tier uses the module output; AKS tier uses the azurerm resource.
  # This variable is referenced by providers.tf, argocd.tf, and gateway.tf.
  # For EKS: cluster_endpoint, cluster_certificate_authority_data come from module.eks
  # For AKS: they come from azurerm_kubernetes_cluster.main.kube_config[0]
  #
  # NOTE: The actual cluster reference is kept as separate references in each
  # file rather than a single local because the EKS module and Azure resource
  # have different output shapes. This keeps each tier's config self-contained.

  # In-memory kubeconfig generated from EKS module output.
  # Used by external data sources (argocd.tf) and local-exec scripts (gateway.tf)
  # that need a kubeconfig file but shouldn't require aws eks update-kubeconfig.
  eks_kubeconfig = jsonencode({
    apiVersion = "v1"
    kind       = "Config"
    clusters = [
      {
        name = module.eks.cluster_name
        cluster = {
          server                   = module.eks.cluster_endpoint
          certificate-authority-data = module.eks.cluster_certificate_authority_data
        }
      }
    ]
    contexts = [
      {
        name = module.eks.cluster_name
        context = {
          cluster = module.eks.cluster_name
          user    = module.eks.cluster_name
        }
      }
    ]
    current-context = module.eks.cluster_name
    users = [
      {
        name = module.eks.cluster_name
        user = {
          exec = {
            apiVersion = "client.authentication.k8s.io/v1beta1"
            command    = "aws"
            args = [
              "eks", "get-token",
              "--cluster-name", module.eks.cluster_name,
              "--region", var.aws_region
            ]
          }
        }
      }
    ]
  })
}
