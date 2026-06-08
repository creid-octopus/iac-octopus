variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "rg-argocd-demo"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "centralus"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
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
  description = "Minimum node count for autoscaler"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum node count for autoscaler"
  type        = number
  default     = 2
}

variable "environment" {
  description = "Value for the 'environment' resource tag"
  type        = string
  default     = "demo"
}

variable "argocd_admin_password_hash" {
  description = "Bcrypt hash of the ArgoCD admin password. Generate with: python3 -c \"import bcrypt; print(bcrypt.hashpw(b'yourpassword', bcrypt.gensalt(10)).decode())\""
  type        = string
  sensitive   = true
}
