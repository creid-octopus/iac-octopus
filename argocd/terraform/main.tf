resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    environment = var.environment
    project     = "argocd-demo"
    managed_by  = "terraform"
  }
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = var.cluster_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = var.cluster_name
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
    environment = var.environment
    project     = "argocd-demo"
    managed_by  = "terraform"
  }
}
