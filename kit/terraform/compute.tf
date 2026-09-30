# ---------- VM (HOSN -> size / admin_* / os_disk+image / nic) ----------
resource "azurerm_network_interface" "vm" {
  count               = var.deploy_vm ? 1 : 0
  name                = "nic-vm01"
  location            = local.location
  resource_group_name = local.rg_name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.snet["web"].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  count                 = var.deploy_vm ? 1 : 0
  name                  = "vm01"
  resource_group_name   = local.rg_name
  location              = local.location
  size                  = var.vm_size
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.vm[0].id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# ---------- AKS ----------
resource "azurerm_kubernetes_cluster" "aks" {
  count                     = var.deploy_aks ? 1 : 0
  name                      = "aks-demo"
  location                  = local.location
  resource_group_name       = local.rg_name
  dns_prefix                = "aks-demo"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = 2
    vm_size        = "Standard_D4s_v5"
    vnet_subnet_id = azurerm_subnet.snet["aks"].id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
}
