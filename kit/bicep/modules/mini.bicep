// ========== TYPES ==========
type subnetType = {
  name: string
  prefix: string
}

// ========== PARAMS ==========
@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

// storage
@minLength(3)
@maxLength(24)
@description('Globally unique, lowercase letters and numbers only')
param stgName string = 'st${uniqueString(resourceGroup().id)}'

@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

// network
param vnetName string = 'vnet-demo'
param nsgName string = 'nsg-web'
param vnetAddressPrefix string = '10.0.0.0/16'

@allowed(['443', '80', '22'])
param allowedPort string = '443'

param subnets subnetType[] = [
  { name: 'snet-web', prefix: '10.0.1.0/24' }
  { name: 'snet-pe', prefix: '10.0.2.0/24' }
  { name: 'snet-aks', prefix: '10.0.4.0/22' }
]

// vm
param vmName string = 'vm01'
param adminUsername string = 'azureuser'

@allowed(['Standard_B1s', 'Standard_B2s', 'Standard_D2s_v5'])
param vmSize string = 'Standard_B1s'

@secure()
@description('Contents of ~/.ssh/id_rsa.pub')
param sshPublicKey string

// ========== RESOURCES ==========
resource st1 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: stgName
  location: location
  sku: { name: skuName }
  kind: 'StorageV2'
}

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

// ---- VM (HOSN: Hardware, OS, Storage, Network) ----
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vnet.properties.subnets[0].id } // first subnet (snet-web); implicit dependency on vnet
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: vmName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    hardwareProfile: { vmSize: vmSize }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: 'server'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'StandardSSD_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

// ========== OUTPUTS ==========
output stgName string = st1.name
output vnetId string = vnet.id
output subnetIds array = [for s in subnets: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, s.name)]
output vmPrincipalId string = vm.identity.principalId
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
