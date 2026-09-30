# G-R-P -> TF generates the GUID; you give scope + role + principal
# Same grants as 06-rbac.bicep + the kvRole in 07-security.bicep, all for the app UAMI, all behind deploy_rbac
locals {
  rbac = var.deploy_rbac ? 1 : 0
}

resource "azurerm_role_assignment" "app_kv" {
  count                = local.rbac
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app_reader" {
  count                = local.rbac
  scope                = local.rg_id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app_blob" {
  count                = local.rbac
  scope                = azurerm_storage_account.stg.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "vm_operator" {
  count = local.rbac
  name  = "VM Operator (${local.rg_name})"
  scope = local.rg_id

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
    ]
    not_actions = []
  }

  assignable_scopes = [local.rg_id]
}

resource "azurerm_role_assignment" "app_vm_operator" {
  count              = local.rbac
  scope              = local.rg_id
  role_definition_id = azurerm_role_definition.vm_operator[0].role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.app.principal_id
  principal_type     = "ServicePrincipal"
}
