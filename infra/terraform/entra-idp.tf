# Microsoft Entra ID (Azure AD) app registration for Zitadel OIDC login.
# This allows users to sign in to Zitadel using their Microsoft accounts.

resource "azuread_application" "zitadel_login" {
  display_name     = "${var.project}-${var.environment}-zitadel-login"
  sign_in_audience = "AzureADandPersonalMicrosoftAccount"

  api {
    requested_access_token_version = 2
  }

  optional_claims {
    id_token {
      name = "email"
    }
    id_token {
      name = "preferred_username"
    }
    id_token {
      name = "given_name"
    }
    id_token {
      name = "family_name"
    }
  }

  web {
    redirect_uris = [
      "https://zitadel.${var.environment}.${var.domain}/idps/callback"
    ]
  }

  required_resource_access {
    resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph

    resource_access {
      id   = "37f7f235-527c-4136-accd-4a02d197296e" # openid
      type = "Scope"
    }
    resource_access {
      id   = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0" # email
      type = "Scope"
    }
    resource_access {
      id   = "14dad69e-099b-42c9-810b-d002981feec1" # profile
      type = "Scope"
    }
  }
}

resource "azuread_application_password" "zitadel_login" {
  application_id = azuread_application.zitadel_login.id
  display_name   = "zitadel-oidc-${var.environment}"
  end_date       = "2027-12-31T00:00:00Z"
}

resource "azurerm_key_vault_secret" "microsoft_idp_client_id" {
  name         = "${local.name_prefix}-microsoft-idp-client-id"
  value        = azuread_application.zitadel_login.client_id
  key_vault_id = azurerm_key_vault.main.id
}

resource "azurerm_key_vault_secret" "microsoft_idp_client_secret" {
  name         = "${local.name_prefix}-microsoft-idp-client-secret"
  value        = azuread_application_password.zitadel_login.value
  key_vault_id = azurerm_key_vault.main.id
}
