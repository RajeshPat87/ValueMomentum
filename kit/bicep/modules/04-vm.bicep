// Deploy: az deployment group create -g rg-demo -f 04-vm.bicep -p subnetId=<id> sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"
// VM mnemonic HOSN: Hardware, OS, Storage, Network

// ========== TYPES ==========
type imageType = {
  publisher: string
  offer: string
  sku: string
  version: string
}

// ========== PARAMS ==========
@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

@minLength(1)
@maxLength(64)
param vmName string = 'vm01'

param adminUsername string = 'azureuser'

@allowed(['Standard_B1s', 'Standard_B2s', 'Standard_D2s_v5'])
param vmSize string = 'Standard_B1s'

@allowed(['Standard_LRS', 'StandardSSD_LRS', 'Premium_LRS'])
param osDiskType string = 'StandardSSD_LRS'

param image imageType = {
  publisher: 'Canonical'
  offer: 'ubuntu-24_04-lts'
  sku: 'server'
  version: 'latest'
}

@description('Subnet resource ID for the NIC (from 03-network webSubnetId)')
param subnetId string

@description('Contents of ~/.ssh/id_rsa.pub')
param sshPublicKey string

// ========== RESOURCES ==========
resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-${vmName}'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: subnetId }
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
      imageReference: image
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: osDiskType }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

// ========== OUTPUTS ==========
output vmId string = vm.id
output vmPrincipalId string = vm.identity.principalId
output vmPrivateIp string = nic.properties.ipConfigurations[0].properties.privateIPAddress
