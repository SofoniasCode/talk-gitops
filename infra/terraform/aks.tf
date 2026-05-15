resource "azurerm_kubernetes_cluster" "main" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${local.name_prefix}-aks"
  kubernetes_version  = var.aks_kubernetes_version
  tags                = local.common_tags

  default_node_pool {
    name                         = "default"
    node_count                   = var.aks_node_count
    vm_size                      = var.aks_vm_size
    max_pods                     = 110
    temporary_name_for_rotation  = "tmpdefault"

    upgrade_settings {
      max_surge = "10%"
    }
  }

  identity {
    type = "SystemAssigned"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  network_profile {
    network_plugin = "azure"
    dns_service_ip = "10.2.0.10"
    service_cidr   = "10.2.0.0/16"
  }
}

locals {
  aks_outbound_ip_id = tolist(azurerm_kubernetes_cluster.main.network_profile[0].load_balancer_profile[0].effective_outbound_ips)[0]
}

data "azurerm_public_ip" "aks_outbound" {
  name                = split("/", local.aks_outbound_ip_id)[8]
  resource_group_name = azurerm_kubernetes_cluster.main.node_resource_group
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
  role_definition_name             = "AcrPull"
  scope                            = azurerm_container_registry.main.id
  skip_service_principal_aad_check = true
}
