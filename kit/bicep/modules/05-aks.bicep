// Deploy: az deployment group create -g rg-demo -f 05-aks.bicep -p subnetId=<id>

// ========== TYPES ==========
type aksNetworkType = {
  serviceCidr: string // must NOT overlap the VNet
  dnsServiceIP: string // must sit inside serviceCidr
}

// ========== PARAMS ==========
@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

@minLength(1)
@maxLength(63)
param aksName string = 'aks-demo'

@minValue(1)
@maxValue(5)
param nodeCount int = 2

@allowed(['Standard_D2s_v5', 'Standard_D4s_v5'])
param nodeVmSize string = 'Standard_D4s_v5'

@description('Subnet resource ID for the node pool (from 03-network aksSubnetId)')
param subnetId string

param aksNetwork aksNetworkType = {
  serviceCidr: '172.16.0.0/16'
  dnsServiceIP: '172.16.0.10'
}

// ========== RESOURCES ==========
resource aks 'Microsoft.ContainerService/managedClusters@2024-09-01' = {
  name: aksName
  location: location
  identity: { type: 'SystemAssigned' }
  properties: {
    dnsPrefix: aksName
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: nodeCount
        vmSize: nodeVmSize
        osType: 'Linux'
        vnetSubnetID: subnetId
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: aksNetwork.serviceCidr
      dnsServiceIP: aksNetwork.dnsServiceIP
    }
    aadProfile: {
      managed: true
      enableAzureRBAC: true
    }
    oidcIssuerProfile: { enabled: true }
    securityProfile: {
      workloadIdentity: { enabled: true }
    }
  }
}

// ========== OUTPUTS ==========
output aksId string = aks.id
output aksName string = aks.name
output oidcIssuer string = aks.properties.oidcIssuerProfile.issuerURL
