output "rg_name" {
  value = local.rg_name
}

output "kv_name" {
  value = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}

output "stg_name" {
  value = azurerm_storage_account.stg.name
}

output "subnet_ids" {
  value = { for k, s in azurerm_subnet.snet : k => s.id }
}

output "aks_oidc_issuer" {
  value = var.deploy_aks ? azurerm_kubernetes_cluster.aks[0].oidc_issuer_url : null
}
