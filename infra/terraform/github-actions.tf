# GitHub Actions OIDC federation for pushing images to ACR.
# This allows GitHub Actions in the talk app repo to authenticate
# with Azure without storing credentials, using OIDC federation.

resource "azuread_application" "github_actions" {
  display_name = "${local.name_prefix}-github-actions"
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# The azuread provider lowercases the federated credential subject, but
# GitHub sends case-sensitive org names. We use local-exec to preserve
# the exact casing from var.github_repo.
resource "terraform_data" "github_actions_federated_creds" {
  input = {
    app_id      = azuread_application.github_actions.client_id
    github_repo = var.github_repo
    prefix      = local.name_prefix
  }

  provisioner "local-exec" {
    command = <<-EOT
      for BRANCH in dev main; do
        az ad app federated-credential create \
          --id "${self.input.app_id}" \
          --parameters "{
            \"name\": \"github-$BRANCH\",
            \"issuer\": \"https://token.actions.githubusercontent.com\",
            \"subject\": \"repo:${self.input.github_repo}:ref:refs/heads/$BRANCH\",
            \"audiences\": [\"api://AzureADTokenExchange\"]
          }" --output none 2>/dev/null || true
      done
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      for CRED_ID in $(az ad app federated-credential list --id "${self.input.app_id}" --query '[].id' -o tsv 2>/dev/null); do
        az ad app federated-credential delete --id "${self.input.app_id}" --federated-credential-id "$CRED_ID" 2>/dev/null || true
      done
    EOT
  }
}

resource "azurerm_role_assignment" "github_actions_acr_push" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPush"
  principal_id         = azuread_service_principal.github_actions.object_id
}
