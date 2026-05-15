resource "azurerm_dns_zone" "dev" {
  name                = "${var.environment}.${var.domain}"
  resource_group_name = azurerm_resource_group.main.name
  tags                = local.common_tags
}

# A records will be added after Envoy Gateway provisions a LoadBalancer IP.
# For now, output the nameservers so the user can delegate from GoDaddy.
