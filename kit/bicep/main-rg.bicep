// RG-scope entry point: deploys into an EXISTING resource group
// Deploy: az deployment group create -g <rg> -p main-rg.bicepparam
param location string = resourceGroup().location
param deployVm bool = true
param deployAks bool = false
param deployRbac bool = false // playground SPs usually can't write role assignments
param kvPurgeProtection bool = true
param kvSoftDeleteDays int = 90

@secure()
param sshPublicKey string
@secure()
param dbPassword string

module storage 'modules/02-storage.bicep' = {
  name: 'storage'
  params: { location: location }
}

module network 'modules/03-network.bicep' = {
  name: 'network'
  params: { location: location }
}

module vm 'modules/04-vm.bicep' = if (deployVm) {
  name: 'vm'
  params: {
    location: location
    subnetId: network.outputs.webSubnetId
    sshPublicKey: sshPublicKey
  }
}

module aks 'modules/05-aks.bicep' = if (deployAks) {
  name: 'aks'
  params: {
    location: location
    subnetId: network.outputs.aksSubnetId
  }
}

module security 'modules/07-security.bicep' = {
  name: 'security'
  params: {
    location: location
    vnetId: network.outputs.vnetId
    peSubnetId: network.outputs.peSubnetId
    dbPassword: dbPassword
    deployRoleAssignment: deployRbac
    enablePurgeProtection: kvPurgeProtection
    softDeleteRetentionInDays: kvSoftDeleteDays
  }
}

module rbac 'modules/06-rbac.bicep' = if (deployRbac) {
  name: 'rbac'
  params: {
    principalId: security.outputs.uamiPrincipalId
    stgName: storage.outputs.stgName
  }
}

output kvName string = security.outputs.kvName
output stgName string = storage.outputs.stgName
