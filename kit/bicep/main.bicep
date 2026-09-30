// One-shot: RG + everything via modules
// Deploy: az deployment sub create -l eastus -f main.bicep -p main.bicepparam
targetScope = 'subscription'

param rgName string = 'rg-demo'
param location string = 'eastus'
param deployVm bool = true
param deployAks bool = false
@secure()
param sshPublicKey string
@secure()
param dbPassword string = ''

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
}

module storage 'modules/02-storage.bicep' = {
  name: 'storage'
  scope: rg
  params: { location: location }
}

module network 'modules/03-network.bicep' = {
  name: 'network'
  scope: rg
  params: { location: location }
}

module vm 'modules/04-vm.bicep' = if (deployVm) {
  name: 'vm'
  scope: rg
  params: {
    location: location
    subnetId: network.outputs.webSubnetId
    sshPublicKey: sshPublicKey
  }
}

module aks 'modules/05-aks.bicep' = if (deployAks) {
  name: 'aks'
  scope: rg
  params: {
    location: location
    subnetId: network.outputs.aksSubnetId
  }
}

module security 'modules/07-security.bicep' = {
  name: 'security'
  scope: rg
  params: {
    location: location
    vnetId: network.outputs.vnetId
    peSubnetId: network.outputs.peSubnetId
    dbPassword: dbPassword
  }
}

module rbac 'modules/06-rbac.bicep' = {
  name: 'rbac'
  scope: rg
  params: {
    principalId: security.outputs.uamiPrincipalId
    stgName: storage.outputs.stgName
  }
}

output rgId string = rg.id
output kvName string = security.outputs.kvName
