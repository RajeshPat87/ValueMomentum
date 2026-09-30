resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = local.location
  resource_group_name = local.rg_name

  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-demo"
  location            = local.location
  resource_group_name = local.rg_name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "snet" {
  for_each             = var.subnets
  name                 = "snet-${each.key}"
  resource_group_name  = local.rg_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value]
}

resource "azurerm_subnet_network_security_group_association" "snet" {
  for_each                  = azurerm_subnet.snet # every subnet, as in 03-network.bicep
  subnet_id                 = each.value.id
  network_security_group_id = azurerm_network_security_group.web.id
}
