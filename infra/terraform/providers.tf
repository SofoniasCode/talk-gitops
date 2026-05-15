terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Each environment uses a separate state file.
  # Initialize with: terraform init -backend-config="key=<env>.terraform.tfstate"
  # Example:
  #   terraform init -backend-config="key=dev.terraform.tfstate"
  #   terraform init -backend-config="key=stg.terraform.tfstate" -reconfigure
  backend "azurerm" {
    resource_group_name  = "talk-tfstate-rg"
    storage_account_name = "talktfstate"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id = var.subscription_id
}

provider "azuread" {}
