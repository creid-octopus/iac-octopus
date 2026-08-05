variable "resource_group_name" {
  description = "Base name for the Azure resource group. The environment is appended automatically: rg-argocd-demo-development."
  type        = string
  default     = "rg-argocd-demo"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "cluster_name" {
  description = "Base name for the AKS cluster. The environment is appended automatically: aks-argocd-demo-development."
  type        = string
  default     = "aks-argocd-demo"
}

variable "kubernetes_version" {
  description = "Kubernetes version to use. Null uses the latest default for the region."
  type        = string
  default     = null
}

variable "node_size" {
  description = "VM size for AKS nodes"
  type        = string
  default     = "Standard_B2s"
}

variable "node_min_count" {
  description = "Minimum node count for autoscaler. Set to 2 for demo clusters — a single Standard_B2s can't fit ArgoCD + kube-prometheus-stack + Octopus agents without CPU pressure."
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum node count for autoscaler"
  type        = number
  default     = 2
}

variable "environment" {
  description = "Environment name — appended to all resource names and used as the Terraform state key suffix. Must match the Octopus environment name in lowercase (e.g. development, test, production). No default: must be set explicitly per run."
  type        = string
}

variable "argocd_admin_password_hash" {
  description = "Bcrypt hash of the ArgoCD admin password. Generate with: python3 -c \"import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt(10)).decode())\""
  type        = string
  sensitive   = true
}

variable "argocd_admin_password" {
  description = "Plaintext ArgoCD admin password — used only by the local-exec token generation script, never stored in state"
  type        = string
  sensitive   = true
}

variable "argocd_web_ui_url" {
  description = "Override the ArgoCD Web UI URL for Octopus registration. Leave empty to compute automatically from the LoadBalancer IP."
  type        = string
  default     = ""
}

variable "argocd_insecure" {
  description = "Skip TLS verification on the gRPC connection from the gateway to ArgoCD (true for self-signed cert)"
  type        = bool
  default     = true
}

# ─── Octopus Deploy ────────────────────────────────────────────────────────

variable "octopus_api_url" {
  description = "Octopus Deploy HTTP API URL"
  type        = string
  default     = "https://demo.octopus.app"
}

variable "octopus_grpc_url" {
  description = "Octopus Deploy gRPC URL including port. Octopus Cloud uses 8443 for gRPC (443 is the REST API)."
  type        = string
  default     = "demo.octopus.app:8443"
}

variable "octopus_grpc_plaintext" {
  description = "Disable TLS on the Octopus gRPC connection — only for local/dev setups"
  type        = bool
  default     = false
}

variable "octopus_api_key" {
  description = "Octopus Deploy API key used to register the gateway"
  type        = string
  sensitive   = true
}

variable "octopus_space_id" {
  description = "Octopus Deploy Space ID the gateway registers into"
  type        = string
  default     = "Spaces-3705"
}

variable "octopus_environments" {
  description = "Octopus Deploy environment names to associate with this gateway"
  type        = list(string)
  default     = ["#{Terraform.Environment.Name}"]
}

# ─── Gateway ───────────────────────────────────────────────────────────────

variable "gateway_namespace" {
  description = "Kubernetes namespace for the Octopus ArgoCD Gateway"
  type        = string
  default     = "octopus-argocd-gateway"
}

variable "gateway_name" {
  description = "Base name for the ArgoCD gateway as it appears in Octopus Deploy. The environment is appended automatically: argocd-demo-development."
  type        = string
  default     = "argocd-demo"
}

variable "gateway_chart_version" {
  description = "Helm chart version for the Octopus ArgoCD Gateway. Check: https://hub.docker.com/r/octopusdeploy/octopus-argocd-gateway-chart/tags"
  type        = string
  default     = "1.23.0"
}

# ─── Octopus space name ─────────────────────────────────────────────────────
# The Helm chart uses the space name (not ID) when registering the agent.
variable "octopus_space_name" {
  description = "Octopus Deploy Space name — used by the Kubernetes agent Helm chart (chart takes name, not ID)"
  type        = string
  default     = "CReid - Sandbox"
}

# ─── Kubernetes Agent ───────────────────────────────────────────────────────

variable "kubernetes_agent_name" {
  description = "Name for the Kubernetes agent deployment target in Octopus. Also used as the Helm release name — must be unique per cluster."
  type        = string
  default     = "aks-argocd-demo"
}

variable "kubernetes_agent_namespace" {
  description = "Kubernetes namespace to install the agent into"
  type        = string
  default     = "octopus-k8s-agent"
}

variable "kubernetes_agent_roles" {
  description = "Target tags (roles) to assign to the Kubernetes agent deployment target"
  type        = list(string)
  default     = ["k8s-agent"]
}

variable "kubernetes_agent_chart_version" {
  description = "Helm chart major version constraint for the Kubernetes agent. Specify the major version to prevent breaking changes. Check: https://hub.docker.com/r/octopusdeploy/kubernetes-agent/tags"
  type        = string
  default     = "3.*.*"
}
