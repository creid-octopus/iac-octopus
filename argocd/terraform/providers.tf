terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.0"
    }
    octopusdeploy = {
      source  = "OctopusDeploy/octopusdeploy"
      version = "~> 1.0"
    }
  }

  # Backend: AzureRM blob storage — shared across both AKS and EKS tiers.
  # The same storage account holds state for any cloud provider.
  # Octopus substitutes #{...} in files before running terraform init,
  # so this hydrates to e.g. "creid-argocd-demo-development-aks.tfstate" or
  # "creid-argocd-demo-development-eks.tfstate" at runtime.
  # Local runs will fail until this is replaced manually or via TF_CLI_ARGS_init.
  backend "azurerm" {
    resource_group_name  = "terraform-state"
    storage_account_name = "octotfstate"
    container_name       = "terraform-state"
    key                  = "creid-argocd-demo-#{Octopus.Environment.Name | ToLower}-#{Project.Terraform.CloudProvider}.tfstate"
  }
}

# ─── Azure Provider (AKS tier — disabled by default for EKS) ─────────────────
# provider "azurerm" {
#   features {}
#   # Auth: Azure CLI (az login) — no credentials in code
# }

# ─── AWS Provider (EKS tier) ─────────────────────────────────────────────
# Auth: AWS CLI (aws configure) or IAM role on the worker.
# No access keys in code — uses the worker's IAM execution role.
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      environment  = local.env
      cluster_name = local.cluster_name
      project      = "argocd-demo"
      managed_by   = "terraform"
    }
  }
}

# ─── Octopus Deploy ────────────────────────────────────────────────────────

provider "octopusdeploy" {
  address  = var.octopus_api_url
  api_key  = var.octopus_api_key
  space_id = var.octopus_space_id
}

# ─── Kubernetes Provider ───────────────────────────────────────────────────
# EKS-style auth: uses aws eks get-token via exec plugin.
# Works with both EKS module output and manual kubeconfig.
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
  }
}

# ─── Helm Provider ─────────────────────────────────────────────────────────
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name, "--region", var.aws_region]
    }
  }
}
