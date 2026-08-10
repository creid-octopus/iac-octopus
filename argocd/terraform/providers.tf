terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.95, < 6.0.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "terraform-state"
    storage_account_name = "octotfstate"
    container_name       = "terraform-state"
    # Octopus substitutes #{...} in files before running terraform init,
    # so this hydrates to e.g. "creid-argocd-demo-development.tfstate" at runtime.
    # Local runs will fail until this is replaced manually or via TF_CLI_ARGS_init.
    key = "creid-argocd-demo-#{Octopus.Environment.Name | ToLower}.tfstate"
  }
}

provider "azurerm" {
  features {}
  # Auth: Azure CLI (az login) — no credentials in code
}

provider "octopusdeploy" {
  address  = var.octopus_api_url
  api_key  = var.octopus_api_key
  space_id = var.octopus_space_id
}

# Keep the AWS provider configured so destroy runs can clean up any legacy
# AWS-managed resources still present in state.
provider "aws" {}

# Both helm and kubernetes providers are configured to connect directly
# to the AKS cluster via its kube_config output — no local kubeconfig required.
provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
  }
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.main.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.main.kube_config[0].cluster_ca_certificate)
}
