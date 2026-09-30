# ---------- Resource group + storage ----------
resource "random_string" "sfx" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name = "demo-${var.env}"
  tags = { env = var.env, managed_by = "terraform" }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "stg" {
  name                            = "st${var.env}${random_string.sfx.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.stg.id
  container_access_type = "private"
}
