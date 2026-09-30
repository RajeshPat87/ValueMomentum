// Deploy: az deployment group create -g <rg> -f 07-security.bicep -p vnetId=<id> peSubnetId=<id>
// Key Vault mnemonic R-S-P-N: RBAC, Soft delete, Purge protection, Network deny

// ========== PARAMS ==========
@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

@minLength(3)
@maxLength(24)
@description('Globally unique; letters, numbers and hyphens')
param kvName string = 'kv-${uniqueString(resourceGroup().id)}'

param uamiName string = 'id-app'

@minValue(7)
@maxValue(90)
param softDeleteRetentionInDays int = 90

@description('Purge protection is permanent once enabled; some policies forbid it')
param enablePurgeProtection bool = true

@allowed(['Disabled', 'Enabled'])
param publicNetworkAccess string = 'Disabled'

@description('VNet resource ID to link the private DNS zone to')
param vnetId string

@description('Subnet resource ID for the private endpoint (from 03-network peSubnetId)')
param peSubnetId string

@secure()
@description('Optional; stored as secret db-password when provided')
param dbPassword string = ''

@description('Set false where the deployer lacks roleAssignments/write (e.g. playground SP)')
param deployRoleAssignment bool = true

// ========== VARIABLES ==========
var kvSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

// ========== RESOURCES ==========
resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: softDeleteRetentionInDays
    enablePurgeProtection: enablePurgeProtection ? true : null // ARM rejects false; omit instead
    publicNetworkAccess: publicNetworkAccess
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
  }
}

// Written via ARM control plane, so it works even with public access disabled
resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(dbPassword)) {
  parent: kv
  name: 'db-password'
  properties: { value: dbPassword }
}

resource kvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployRoleAssignment) {
  name: guid(kv.id, uami.id, kvSecretsUser)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', kvSecretsUser)
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Private endpoint + private DNS: PE -> zone -> vnet link -> zone group
resource pe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${kv.name}'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'psc-kv'
        properties: {
          privateLinkServiceId: kv.id
          groupIds: ['vault']
        }
      }
    ]
  }
}

resource dnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.vaultcore.azure.net'
  location: 'global'
}

resource dnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: dnsZone
  name: 'link-vnet'
  location: 'global'
  properties: {
    virtualNetwork: { id: vnetId }
    registrationEnabled: false
  }
}

resource dnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: pe
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'kv'
        properties: { privateDnsZoneId: dnsZone.id }
      }
    ]
  }
}

// ========== OUTPUTS ==========
output kvName string = kv.name
output kvUri string = kv.properties.vaultUri
output uamiId string = uami.id
output uamiPrincipalId string = uami.properties.principalId
