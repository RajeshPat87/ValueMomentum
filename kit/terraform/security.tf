resource "azurerm_user_assigned_identity" "app" {
  name                = "id-app"
  location            = local.location
  resource_group_name = local.rg_name
}

# R-S-P-N: RBAC, Soft delete, Purge protection, Network deny
resource "azurerm_key_vault" "kv" {
  name                          = "kv-${var.env}-${random_string.sfx.result}"
  location                      = local.location
  resource_group_name           = local.rg_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.kv_purge_protection
  soft_delete_retention_days    = var.kv_soft_delete_days
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# Written through the ARM control plane (same as 07-security.bicep), so it works while public access is disabled
# and the deployer needs no data-plane role. azurerm_key_vault_secret would need network access to the vault.
resource "azapi_resource" "db_password" {
  count          = nonsensitive(var.db_password != "") ? 1 : 0
  type           = "Microsoft.KeyVault/vaults/secrets@2023-07-01"
  name           = "db-password"
  parent_id      = azurerm_key_vault.kv.id
  sensitive_body = { properties = { value = var.db_password } }
}

resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.rg_name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "link-vnet"
  resource_group_name   = local.rg_name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-${azurerm_key_vault.kv.name}"
  location            = local.location
  resource_group_name = local.rg_name
  subnet_id           = azurerm_subnet.snet["pe"].id

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

# Governance: built-in "Allowed locations" (policyAssignments/write, so it sits behind deploy_rbac)
resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  count                = var.deploy_rbac ? 1 : 0
  name                 = "allowed-locations"
  resource_group_id    = local.rg_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  parameters = jsonencode({
    listOfAllowedLocations = { value = ["eastus", "westeurope"] }
  })
}
