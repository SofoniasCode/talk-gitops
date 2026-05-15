output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "key_vault_name" {
  value = azurerm_key_vault.main.name
}

output "key_vault_url" {
  value = azurerm_key_vault.main.vault_uri
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.main.fqdn
}

output "postgres_admin_username" {
  value = var.postgres_admin_username
}

output "dns_zone_name" {
  value = azurerm_dns_zone.dev.name
}

output "dns_zone_nameservers" {
  value       = azurerm_dns_zone.dev.name_servers
  description = "Add these as NS records for 'dev' in GoDaddy DNS for telodev.com"
}

output "eso_managed_identity_client_id" {
  value       = azurerm_user_assigned_identity.eso.client_id
  description = "Set in azure-workload-identity-serviceaccount.yaml annotation"
}

output "eso_managed_identity_tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Set in azure-workload-identity-serviceaccount.yaml annotation"
}

output "cert_manager_identity_client_id" {
  value       = azurerm_user_assigned_identity.cert_manager.client_id
  description = "Set in cert-manager ServiceAccount annotation"
}

output "microsoft_idp_client_id" {
  value       = azuread_application.zitadel_login.client_id
  description = "Entra ID app client ID for Zitadel Microsoft login"
}

output "microsoft_idp_tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Entra ID tenant ID for Zitadel Microsoft login"
}

output "github_actions_client_id" {
  value       = azuread_application.github_actions.client_id
  description = "Set as AZURE_CLIENT_ID secret in GitHub Actions"
}

output "github_actions_tenant_id" {
  value       = data.azurerm_client_config.current.tenant_id
  description = "Set as AZURE_TENANT_ID secret in GitHub Actions"
}

output "github_actions_subscription_id" {
  value       = var.subscription_id
  description = "Set as AZURE_SUBSCRIPTION_ID secret in GitHub Actions"
}
