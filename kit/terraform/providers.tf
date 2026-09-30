terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    azapi   = { source = "azure/azapi", version = "~> 2.0" } # ARM control-plane writes (Key Vault secret)
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }

  # Partial backend: deploy.sh passes resource_group_name / storage_account_name / container_name / key at init.
  # Create the storage account once with ./bootstrap-state.sh. Auth follows ARM_* env (client secret locally, OIDC in the pipeline).
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id = var.subscription_id # mandatory in azurerm 4.x
  # 4.x registers resource providers at subscription scope by default; an RG-scoped SPN (KodeKloud) is denied that.
  # On a fresh subscription, register them once: az provider register -n Microsoft.KeyVault (etc.)
  resource_provider_registrations = "none"
}

provider "azapi" {}

data "azurerm_client_config" "current" {}
