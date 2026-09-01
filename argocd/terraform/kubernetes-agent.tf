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
  # https://creid.octopus.app -> https://polling.creid.octopus.app
  octopus_polling_url = replace(var.octopus_api_url, "https://", "https://polling.")
  # Environment-suffixed agent name in Octopus (e.g. creid-aks-meta-nonproduction)
  agent_name          = "${var.kubernetes_agent_name}-${var.environment}"
  # Agent names for extra clusters (e.g. creid-aks-c02-nonproduction)
  extra_agent_names   = { for k, v in local.extra_clusters : k => "${var.kubernetes_agent_name}-${k}-${var.environment}" }
  # Map environment slugs to Octopus environment display names (case-sensitive lookup)
  # REVIEW/SIMPLIFY LATER: This env-slug-to-name mapping is fragile. The intent is to look up Octopus
  # environment IDs so they can be attached to the Kubernetes agent deployment target.
  # Consider: pass environment IDs directly as a variable instead of resolving by name,
  # or use a dedicated variable for environment IDs vs names.
  environment_names   = { for slug in split(",", var.octopus_environments) : slug => title(slug) }
}

# Pre-generate the agent identity — cert and polling subscription URI.
# Both are created locally by the provider; no Octopus round-trip at this stage.
# Octopus registers the target expecting these values, and the Helm chart installs
# an agent that presents them — no time-limited bearer token required.
resource "octopusdeploy_polling_subscription_id" "k8s_agent" {}
resource "octopusdeploy_tentacle_certificate" "k8s_agent" {}

# Look up environment IDs for the target registration.
# Uses for_each over the slug→name map to resolve actual Octopus environment names.
data "octopusdeploy_environments" "k8s_agent" {
  for_each = local.environment_names
  name     = each.value
  space_id = var.octopus_space_id
  skip     = 0
  take     = 1
}

# Pre-register the deployment target in Octopus Deploy.
# Creates the target record with the expected cert thumbprint and subscription URI
# before the agent is installed. When the agent connects, Octopus matches it here.
resource "octopusdeploy_kubernetes_agent_deployment_target" "k8s_agent" {
  name         = local.agent_name
  space_id     = var.octopus_space_id
  environments = flatten([for name, env in data.octopusdeploy_environments.k8s_agent : [for e in env.environments : e.id] if length(env.environments) > 0])
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
  name       = local.agent_name
  repository = "oci://registry-1.docker.io"
  chart      = "octopusdeploy/kubernetes-agent"
  version    = var.kubernetes_agent_chart_version
  namespace  = kubernetes_namespace.k8s_agent.metadata[0].name
  atomic     = false
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
    value = split(",", var.octopus_environments)
  }
  set_list {
    name  = "agent.deploymentTarget.initial.tags"
    value = var.kubernetes_agent_roles
  }

  # Custom tooling image for Kubernetes agent deployment target (replace default Octopus tooling)
  set {
    name  = "scriptPods.deploymentTarget.image.repository"
    value = "ghcr.io/creid-octopus/demo-kubernetes-krane-toolbox"
  }
  set {
    name  = "scriptPods.deploymentTarget.image.tag"
    value = "1"
  }
  set {
    name  = "scriptPods.deploymentTarget.image.pullPolicy"
    value = "Always"
  }
}

# ── Extra Cluster Agents (c02, c03) ──────────────────────────────────────────
# Each extra cluster gets its own Octopus deployment target + agent Helm install.
# Agent names: creid-aks-c02-nonproduction, creid-aks-c03-nonproduction.
#
# NOTE: The default helm/kubernetes providers point at c01, so per-cluster
# resources use explicit provider aliases (helm.c02, kubernetes.c03, etc.).

# Per-cluster identity — unique cert + subscription for each target.
resource "octopusdeploy_polling_subscription_id" "extra_agent" {
  for_each = local.extra_clusters
}

resource "octopusdeploy_tentacle_certificate" "extra_agent" {
  for_each = local.extra_clusters
}

# Register the deployment target in Octopus before installing the agent.
resource "octopusdeploy_kubernetes_agent_deployment_target" "extra_agent" {
  for_each = local.extra_clusters

  name         = local.extra_agent_names[each.key]
  space_id     = var.octopus_space_id
  environments = flatten([for name, env in data.octopusdeploy_environments.k8s_agent : [for e in env.environments : e.id] if length(env.environments) > 0])
  roles        = var.kubernetes_agent_roles

  thumbprint = octopusdeploy_tentacle_certificate.extra_agent[each.key].thumbprint
  uri        = octopusdeploy_polling_subscription_id.extra_agent[each.key].polling_uri
}

# ── Agent namespace + Helm install on c02 ────────────────────────────────────

resource "kubernetes_namespace" "extra_agent_c02" {
  metadata { name = var.kubernetes_agent_namespace }
  depends_on = [azurerm_kubernetes_cluster.extra]
  provider = kubernetes.c02
}

resource "helm_release" "extra_agent_c02" {
  name       = local.extra_agent_names["c02"]
  repository = "oci://registry-1.docker.io"
  chart      = "octopusdeploy/kubernetes-agent"
  version    = var.kubernetes_agent_chart_version
  namespace  = kubernetes_namespace.extra_agent_c02.metadata[0].name
  atomic     = false
  timeout    = 300
  wait       = true
  depends_on = [octopusdeploy_kubernetes_agent_deployment_target.extra_agent]
  provider = helm.c02

  set {
    name  = "agent.acceptEula"
    value = "Y"
  }
  set {
    name  = "agent.name"
    value = octopusdeploy_kubernetes_agent_deployment_target.extra_agent["c02"].name
  }
  set {
    name  = "agent.serverUrl"
    value = var.octopus_api_url
  }
  set_list {
    name  = "agent.serverCommsAddresses"
    value = [local.octopus_polling_url]
  }
  set {
    name  = "agent.serverSubscriptionId"
    value = octopusdeploy_polling_subscription_id.extra_agent["c02"].polling_uri
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
    value = octopusdeploy_tentacle_certificate.extra_agent["c02"].base64
  }

  set_list {
    name  = "agent.deploymentTarget.initial.environments"
    value = split(",", var.octopus_environments)
  }
  set_list {
    name  = "agent.deploymentTarget.initial.tags"
    value = var.kubernetes_agent_roles
  }

  # Custom tooling image for Kubernetes agent deployment target (replace default Octopus tooling)
  set {
    name  = "scriptPods.deploymentTarget.image.repository"
    value = "ghcr.io/creid-octopus/demo-kubernetes-krane-toolbox"
  }
  set {
    name  = "scriptPods.deploymentTarget.image.tag"
    value = "1"
  }
  set {
    name  = "scriptPods.deploymentTarget.image.pullPolicy"
    value = "Always"
  }
}

# ── Agent namespace + Helm install on c03 ────────────────────────────────────

resource "kubernetes_namespace" "extra_agent_c03" {
  metadata { name = var.kubernetes_agent_namespace }
  depends_on = [azurerm_kubernetes_cluster.extra]
  provider = kubernetes.c03
}

resource "helm_release" "extra_agent_c03" {
  name       = local.extra_agent_names["c03"]
  repository = "oci://registry-1.docker.io"
  chart      = "octopusdeploy/kubernetes-agent"
  version    = var.kubernetes_agent_chart_version
  namespace  = kubernetes_namespace.extra_agent_c03.metadata[0].name
  atomic     = false
  timeout    = 300
  wait       = true
  depends_on = [octopusdeploy_kubernetes_agent_deployment_target.extra_agent]
  provider = helm.c03

  set {
    name  = "agent.acceptEula"
    value = "Y"
  }
  set {
    name  = "agent.name"
    value = octopusdeploy_kubernetes_agent_deployment_target.extra_agent["c03"].name
  }
  set {
    name  = "agent.serverUrl"
    value = var.octopus_api_url
  }
  set_list {
    name  = "agent.serverCommsAddresses"
    value = [local.octopus_polling_url]
  }
  set {
    name  = "agent.serverSubscriptionId"
    value = octopusdeploy_polling_subscription_id.extra_agent["c03"].polling_uri
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
    value = octopusdeploy_tentacle_certificate.extra_agent["c03"].base64
  }

  set_list {
    name  = "agent.deploymentTarget.initial.environments"
    value = split(",", var.octopus_environments)
  }
  set_list {
    name  = "agent.deploymentTarget.initial.tags"
    value = var.kubernetes_agent_roles
  }

  # Custom tooling image for Kubernetes agent deployment target (replace default Octopus tooling)
  set {
    name  = "scriptPods.deploymentTarget.image.repository"
    value = "ghcr.io/creid-octopus/demo-kubernetes-krane-toolbox"
  }
  set {
    name  = "scriptPods.deploymentTarget.image.tag"
    value = "1"
  }
  set {
    name  = "scriptPods.deploymentTarget.image.pullPolicy"
    value = "Always"
  }
}
