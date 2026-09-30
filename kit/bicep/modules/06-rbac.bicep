// Deploy: az deployment group create -g rg-demo -f 06-rbac.bicep -p principalId=<objId> stgName=<name>
// Mnemonic G-R-P: Guid name, RoleDefinitionId, PrincipalId

// ========== PARAMS ==========
@minLength(36)
@maxLength(36)
@description('Object ID (GUID) of the identity receiving the roles')
param principalId string

@allowed(['ServicePrincipal', 'User', 'Group'])
param principalType string = 'ServicePrincipal'

@minLength(3)
@maxLength(24)
@description('Existing storage account to scope the blob role to')
param stgName string

@minLength(1)
param customRoleActions string[] = [
  'Microsoft.Compute/virtualMachines/read'
  'Microsoft.Compute/virtualMachines/start/action'
  'Microsoft.Compute/virtualMachines/restart/action'
]

// ========== VARIABLES ==========
var roles = {
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
  blobContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
}

// ========== RESOURCES ==========
resource st 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: stgName
}

// 1. RG scope (default scope = the deployment's RG)
resource rgReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, roles.reader)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.reader)
    principalId: principalId
    principalType: principalType
  }
}

// 2. Resource scope
resource blobWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, principalId, roles.blobContributor)
  scope: st
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.blobContributor)
    principalId: principalId
    principalType: principalType
  }
}

// 3. Custom role, assignable to this RG
resource vmOperator 'Microsoft.Authorization/roleDefinitions@2022-04-01' = {
  name: guid(resourceGroup().id, 'vm-operator')
  properties: {
    roleName: 'VM Operator (${resourceGroup().name})'
    description: 'Read, start and restart VMs'
    type: 'CustomRole'
    permissions: [
      {
        actions: customRoleActions
        notActions: []
      }
    ]
    assignableScopes: [resourceGroup().id]
  }
}

resource vmOperatorAssign 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, 'vm-operator')
  properties: {
    roleDefinitionId: vmOperator.id
    principalId: principalId
    principalType: principalType
  }
}

// ========== OUTPUTS ==========
output rgReaderAssignmentId string = rgReader.id
output blobWriterAssignmentId string = blobWriter.id
output customRoleId string = vmOperator.id
