# ── Octopus Kubernetes Agent ─────────────────────────────────────────────────
# Registers the AKS cluster as a traditional Kubernetes deployment target in
# Octopus using the polling Tentacle agent. Complements the ArgoCD gateway
# (GitOps sync visibility) by enabling Octopus to execute Kubernetes steps
# directly on the cluster.
#
# Unlike the ArgoCD gateway instance, this deployment target is fully managed
# by Terraform — terraform destroy removes it from Octopus automatically.
# No manual cleanup step required.

locals {
  # Derive the polling comms address from the API URL.
  # https://demo.octopus.app -> https://polling.demo.octopus.app
  octopus_polling_url = replace(var.octopus_api_url, "https://", "https://polling.")
}

# Pre-generate the agent identity — cert and polling subscription URI.
# Both are created locally by the provider; no Octopus round-trip at this stage.
# Octopus registers the target expecting these values, and the Helm chart installs
# an agent that presents them — no time-limited bearer token required.
resource "octopusdeploy_polling_subscription_id" "k8s_agent" {}
resource "octopusdeploy_tentacle_certificate" "k8s_agent" {}

# Look up environment IDs for the target registration.
# Uses for_each over var.octopus_environments (names) to resolve to IDs.
data "octopusdeploy_environments" "k8s_agent" {
  for_each = toset(var.octopus_environments)
  name     = each.value
  space_id = var.octopus_space_id
  skip     = 0
  take     = 1
}

# Pre-register the deployment target in Octopus Deploy.
# Creates the target record with the expected cert thumbprint and subscription URI
# before the agent is installed. When the agent connects, Octopus matches it here.
resource "octopusdeploy_kubernetes_agent_deployment_target" "k8s_agent" {
  name         = var.kubernetes_agent_name
  space_id     = var.octopus_space_id
  environments = [for env in data.octopusdeploy_environments.k8s_agent : env.environments[0].id]
  roles        = var.kubernetes_agent_roles

  thumbprint = octopusdeploy_tentacle_certificate.k8s_agent.thumbprint
  uri        = octopusdeploy_polling_subscription_id.k8s_agent.polling_uri
}

resource "kubernetes_namespace" "k8s_agent" {
  metadata {
    name = var.kubernetes_agent_namespace
  }
  depends_on = [azurerm_kubernetes_cluster.main]
}

# Install the Kubernetes agent via Helm.
# The agent connects to Octopus using the pre-generated cert and subscription URI,
# matching the deployment target registered above.
resource "helm_release" "kubernetes_agent" {
  name       = var.kubernetes_agent_name
  repository = "oci://registry-1.docker.io"
  chart      = "octopusdeploy/kubernetes-agent"
  version    = var.kubernetes_agent_chart_version
  namespace  = kubernetes_namespace.k8s_agent.metadata[0].name
  atomic     = true
  timeout    = 300
  wait       = true

  depends_on = [octopusdeploy_kubernetes_agent_deployment_target.k8s_agent]

  set {
    name  = "agent.acceptEula"
    value = "Y"
  }
  set {
    name  = "agent.name"
    value = octopusdeploy_kubernetes_agent_deployment_target.k8s_agent.name
  }
  set {
    name  = "agent.serverUrl"
    value = var.octopus_api_url
  }
  # v3 renamed this field to plural and takes a list
  set_list {
    name  = "agent.serverCommsAddresses"
    value = [local.octopus_polling_url]
  }
  set {
    name  = "agent.serverSubscriptionId"
    value = octopusdeploy_polling_subscription_id.k8s_agent.polling_uri
  }
  set {
    name  = "agent.space"
    value = var.octopus_space_name
  }
  set {
    name  = "agent.deploymentTarget.enabled"
    value = "true"
  }

  set_sensitive {
    name  = "agent.serverApiKey"
    value = var.octopus_api_key
  }
  set_sensitive {
    name  = "agent.certificate"
    value = octopusdeploy_tentacle_certificate.k8s_agent.base64
  }

  set_list {
    name  = "agent.deploymentTarget.initial.environments"
    value = var.octopus_environments
  }
  set_list {
    name  = "agent.deploymentTarget.initial.tags"
    value = var.kubernetes_agent_roles
  }
}
