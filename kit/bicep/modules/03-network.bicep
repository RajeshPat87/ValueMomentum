// Deploy: az deployment group create -g rg-demo -f 03-network.bicep

// ========== TYPES ==========
type subnetType = {
  name: string
  prefix: string
}

// ========== PARAMS ==========
@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

param vnetName string = 'vnet-demo'
param nsgName string = 'nsg-web'
param vnetAddressPrefix string = '10.0.0.0/16'

@allowed(['443', '80', '22'])
param allowedPort string = '443'

@minLength(3)
@description('Order matters: [0] web, [1] private endpoints, [2] aks')
param subnets subnetType[] = [
  { name: 'snet-web', prefix: '10.0.1.0/24' }
  { name: 'snet-pe', prefix: '10.0.2.0/24' }
  { name: 'snet-aks', prefix: '10.0.4.0/22' }
]

// ========== RESOURCES ==========
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-${allowedPort}-In'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: allowedPort
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: [vnetAddressPrefix] }
    subnets: [for s in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.prefix
        networkSecurityGroup: { id: nsg.id }
      }
    }]
  }
}

// ========== OUTPUTS ==========
output vnetId string = vnet.id
output subnetIds array = [for s in subnets: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, s.name)]
output webSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnets[0].name)
output peSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnets[1].name)
output aksSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, subnets[2].name)
