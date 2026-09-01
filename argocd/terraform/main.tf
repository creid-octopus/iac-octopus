locals {
  # Environment-suffixed resource names — all resources include the environment
  # so multiple environments (development, test, production) can coexist independently.
  env            = var.environment
  cluster_name   = "${var.cluster_name}-${local.env}"
  resource_group = "${var.resource_group_name}-${local.env}"

  # Additional AKS clusters beyond the primary (c01).
  # Each entry: key = cluster ID suffix, value = full AKS cluster name.
  extra_clusters = {
    c02 = "creid-aks-meta-nonprod-c02"
    c03 = "creid-aks-meta-nonprod-c03"
  }
}

resource "azurerm_resource_group" "main" {
  name     = local.resource_group
  location = var.location

  tags = {
    environment  = local.env
    cluster_name = local.cluster_name
    project      = "argocd-demo"
    managed_by   = "terraform"
    demo_stack   = "creid-aks"
  }
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = local.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = local.cluster_name
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name    = "system"
    vm_size = var.node_size

    # Autoscaler — scales down to 1 node when idle, up to 2 under load
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count

    os_disk_size_gb = 30

    # Required when changing node pool VM size in-place
    temporary_name_for_rotation = "systemtmp"

    # Declare AKS defaults explicitly to prevent perpetual plan diff
    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  # System-assigned managed identity — no service principal or credential rotation needed
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    # kubenet: simpler networking, no VNet required — appropriate for demos
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  tags = {
    environment    = var.environment
    project        = "argocd-demo"
    managed_by     = "terraform"
    demo_stack     = "creid-aks"
  }
}

# ── Additional AKS Clusters ──────────────────────────────────────────────────
# c02 and c03 share the same resource group as c01 (the primary cluster).
# Each gets its own managed identity and node pool.

resource "azurerm_kubernetes_cluster" "extra" {
  for_each = local.extra_clusters

  name                = each.value
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = each.value
  kubernetes_version  = var.kubernetes_version

  default_node_pool {
    name    = "system"
    vm_size = var.node_size

    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count

    os_disk_size_gb = 30

    # Required when changing node pool VM size in-place
    temporary_name_for_rotation = "systemtmp"

    upgrade_settings {
      drain_timeout_in_minutes      = 0
      max_surge                     = "10%"
      node_soak_duration_in_minutes = 0
    }
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin    = "kubenet"
    load_balancer_sku = "standard"
  }

  tags = {
    environment    = var.environment
    project        = "argocd-demo"
    managed_by     = "terraform"
    demo_stack     = "creid-aks"
  }
}
