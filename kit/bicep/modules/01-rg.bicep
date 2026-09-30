// Deploy: az deployment sub create -l eastus -f 01-rg.bicep -p rgName=rg-demo
targetScope = 'subscription'

// ========== TYPES ==========
type tagsType = {
  env: 'dev' | 'test' | 'prod' // literal union = compile-time allowed values
  owner: string
}

// ========== PARAMS ==========
@minLength(1)
@maxLength(90)
@description('Resource group name (1-90 chars)')
param rgName string = 'rg-demo'

@allowed(['eastus', 'westus', 'centralindia'])
param location string = 'eastus'

param tags tagsType = {
  env: 'dev'
  owner: 'platform'
}

// ========== RESOURCES ==========
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

// ========== OUTPUTS ==========
output rgId string = rg.id
output rgName string = rg.name
