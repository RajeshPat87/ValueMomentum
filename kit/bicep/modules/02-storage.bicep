// Deploy: az deployment group create -g rg-demo -f 02-storage.bicep

// ========== PARAMS ==========
@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

@minLength(3)
@maxLength(24)
@description('Globally unique, lowercase letters and numbers only')
param stgName string = 'st${uniqueString(resourceGroup().id)}'

@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS'])
param skuName string = 'Standard_LRS'

@allowed(['TLS1_2', 'TLS1_3'])
param minimumTlsVersion string = 'TLS1_2'

@minLength(1)
@description('Blob containers to create (3-63 chars, lowercase)')
param containerNames string[] = ['data']

// ========== RESOURCES ==========
resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: stgName
  location: location
  sku: { name: skuName }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: minimumTlsVersion
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: st
  name: 'default'
}

resource containers 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = [for c in containerNames: {
  parent: blob
  name: c
}]

// ========== OUTPUTS ==========
output stgName string = st.name
output stgId string = st.id
output blobEndpoint string = st.properties.primaryEndpoints.blob
