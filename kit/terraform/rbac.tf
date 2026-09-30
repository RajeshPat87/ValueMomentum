# G-R-P -> TF generates the GUID; you give scope + role + principal
resource "azurerm_role_assignment" "deployer_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "app_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app_blob" {
  scope                = azurerm_storage_account.stg.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "vm_reader" {
  count                = var.deploy_vm ? 1 : 0
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine.vm[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "vm_operator" {
  name  = "VM Operator (${azurerm_resource_group.rg.name})"
  scope = azurerm_resource_group.rg.id

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.rg.id]
}

resource "azurerm_role_assignment" "app_vm_operator" {
  scope              = azurerm_resource_group.rg.id
  role_definition_id = azurerm_role_definition.vm_operator.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.app.principal_id
  principal_type     = "ServicePrincipal"
}
