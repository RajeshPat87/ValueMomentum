# ---------- Resource group (existing or created) + storage ----------
resource "random_string" "sfx" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name      = "demo-${var.env}"
  tags      = { env = var.env, managed_by = "terraform" }
  create_rg = var.resource_group_name == ""

  rg_name  = local.create_rg ? azurerm_resource_group.rg[0].name : data.azurerm_resource_group.existing[0].name
  rg_id    = local.create_rg ? azurerm_resource_group.rg[0].id : data.azurerm_resource_group.existing[0].id
  location = local.create_rg ? azurerm_resource_group.rg[0].location : data.azurerm_resource_group.existing[0].location
}

resource "azurerm_resource_group" "rg" {
  count    = local.create_rg ? 1 : 0
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

data "azurerm_resource_group" "existing" {
  count = local.create_rg ? 0 : 1
  name  = var.resource_group_name
}

resource "azurerm_storage_account" "stg" {
  name                            = "st${var.env}${random_string.sfx.result}"
  resource_group_name             = local.rg_name
  location                        = local.location
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
