# GitHub Actions OIDC federation for pushing images to ACR.
# This allows GitHub Actions in the talk app repo to authenticate
# with Azure without storing credentials, using OIDC federation.

resource "azuread_application" "github_actions" {
  display_name = "${local.name_prefix}-github-actions"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

resource "azuread_application_federated_identity_credential" "github_actions_dev" {
  application_id = azuread_application.github_actions.id
  display_name   = "${local.name_prefix}-github-dev"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/dev"
}

resource "azuread_application_federated_identity_credential" "github_actions_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "${local.name_prefix}-github-main"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/main"
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.object_id
}
