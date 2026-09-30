# Azure IaC + Pipelines — Notepad Interview Kit

Every file below is complete and deployable. The Bicep files compile cleanly with the Bicep CLI, the ARM files are valid JSON, and the Terraform and YAML files parse. Resource names and IDs are placeholders you'd swap for your own.

> **Timeline for your intro:** say "ARM since 2016 → Terraform → Bicep since 2021." Bicep was announced in 2020.

---

## 1. The Bicep mental model: Scope → Type → Required props

Every Bicep answer is these three decisions, in this order:

```bicep
targetScope = '<scope>'                               // 1. SCOPE  (omit for resourceGroup)
resource <sym> 'Microsoft.<Service>/<types>@<api>' = { // 2. TYPE
  name: '<name>'                                      // 3. REQUIRED PROPS
  location: '<region>'
  properties: { }
}
```

### Rule 1: file scope == command scope

| `targetScope` | Deploy command |
|---|---|
| *(omitted)* resourceGroup | `az deployment group create -g <rg> -f x.bicep` |
| `'subscription'` | `az deployment sub create -l <region> -f x.bicep` |
| `'managementGroup'` | `az deployment mg create -m <mg> -l <region> -f x.bicep` |
| `'tenant'` | `az deployment tenant create -l <region> -f x.bicep` |

The same command deploys `.json` too. Only the file extension changes.

### Rule 2: direct vs template

| Ask | What you write |
|---|---|
| "Create quickly" | one `az <noun> create` line |
| "Use a template" | `.bicep` (or `.json`) + `az deployment <scope> create` |
| "Reusable / multiple RGs" | sub-scope `main.bicep` + `module ... scope: rg` |

**Resource group, three ways**

```bash
az group create -n rg-demo -l eastus                         # direct
```
```bicep
targetScope = 'subscription'                                 // rg.bicep
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-demo'
  location: 'eastus'
}
```
```bash
az deployment sub create -l eastus -f rg.bicep               # or -f rg.json
```

### Rule 3: type strings follow `Microsoft.<Service>/<camelCasePlural>`

| Resource | Type | Min required props |
|---|---|---|
| RG | `Microsoft.Resources/resourceGroups` | name, location |
| Storage | `Microsoft.Storage/storageAccounts` | + `sku.name`, `kind` |
| VNet | `Microsoft.Network/virtualNetworks` | + `properties.addressSpace.addressPrefixes` |
| Subnet (child) | `Microsoft.Network/virtualNetworks/subnets` | `parent`, `properties.addressPrefix` |
| NSG | `Microsoft.Network/networkSecurityGroups` | name, location |
| NIC | `Microsoft.Network/networkInterfaces` | + `ipConfigurations[].subnet.id` |
| VM | `Microsoft.Compute/virtualMachines` | + HOSN profiles |
| AKS | `Microsoft.ContainerService/managedClusters` | + identity, `dnsPrefix`, `agentPoolProfiles` |
| Identity | `Microsoft.ManagedIdentity/userAssignedIdentities` | name, location |
| Key Vault | `Microsoft.KeyVault/vaults` | + `tenantId`, `sku{family,name}` |
| Secret (child) | `Microsoft.KeyVault/vaults/secrets` | `parent`, `properties.value` |
| Role assignment | `Microsoft.Authorization/roleAssignments` | `guid()` name, `roleDefinitionId`, `principalId` |
| Private endpoint | `Microsoft.Network/privateEndpoints` | + subnet, `privateLinkServiceConnections` |

**API version:** write any recent one (`@2023-05-01`) and say "latest available." Nobody grades it.

### Rule 4: six Notepad syntax traps

1. Use `:` inside objects, not `=`. Terraform muscle memory fights this.
2. Put one property per line with **no commas**. Commas are only for single-line `{ a: 1, b: 2 }`.
3. Strings take single quotes. Interpolation looks like `'kv-${env}'`.
4. For an existing resource: `resource x '<type>@<api>' existing = { name: '...' }`.
5. For a child resource: `parent: vnet`, or give the name as `'vnet/subnet'`.
6. Loops look like `[for s in list: { ... }]`, and conditions look like `= if (flag) { ... }`.

### Mnemonics

| Hook | Meaning |
|---|---|
| **HOSN** | VM = Hardware, OS, Storage, Network profiles |
| **PDAP + 4** | NSG rule = priority, direction, access, protocol + src/dst × address/port |
| **G-R-P** | Role assignment = Guid name, RoleDefinitionId, PrincipalId |
| **R-S-P-N** | Key Vault = RBAC, Soft delete, Purge protection, Network deny |
| **T-R-V-P-S / S-J-S** | YAML root = Trigger, Resources, Variables, Pool, Stages → Jobs → Steps |
| **Curly / Square / Round** | `${{ }}` compile, `$[ ]` runtime, `$( )` right before the task |

### Whiteboard answer: C-S-F-S-V

**C**larify → write the **S**kel­eton (scope + resource line) → **F**ill required props → **S**ecure it (identity, RBAC, network, secrets) → **V**erify (`what-if` / `plan`).

### 7-day drill plan (Notepad, timed, from a blank file)

| Day | Drill | Target |
|---|---|---|
| 1 | RG direct + `rg.bicep` + `rg.json` + deploy commands | 3 min total |
| 2 | `02-storage.bicep`, `03-network.bicep` | 2 + 4 min |
| 3 | `04-vm.bicep` (HOSN), `05-aks.bicep` | 5 + 3 min |
| 4 | `06-rbac.bicep`, `07-security.bicep` | 3 + 6 min |
| 5 | `main.bicep` with modules; the same RG/storage/VNet in Terraform | 5 + 6 min |
| 6 | YAML: simple → jobs → stages → template + consumer → output vars | 15 min |
| 7 | Mock: 3 random asks, speak C-S-F-S-V aloud; revise the tables above | — |

Repeat any file you missed on day +1, +3 and +7.

---

## 2. Kit layout

```
bicep/     main.bicep, main-rg.bicep (+ .bicepparam), deploy.sh, modules/01-rg … 07-security
arm/       rg, storage(+params), network, vm(+KV-reference params), rbac, keyvault
cli/       01-direct-create.sh, 02-deploy-templates.sh
terraform/ providers, variables, main, network, compute, security, rbac, outputs, tfvars, commands
pipelines/ azure-pipelines.yml, templates/ (bicep|terraform)-(validate|deploy), examples/
```

---

## 3. Bicep

### `bicep/modules/01-rg.bicep`

```bicep
// Deploy: az deployment sub create -l eastus -f 01-rg.bicep -p rgName=rg-demo
targetScope = 'subscription'

param rgName string = 'rg-demo'
param location string = 'eastus'

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: { env: 'dev' }
}

output rgId string = rg.id
```

### `bicep/modules/02-storage.bicep`

```bicep
// Deploy: az deployment group create -g rg-demo -f 02-storage.bicep
param location string = resourceGroup().location
param stgName string = 'st${uniqueString(resourceGroup().id)}'

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: stgName
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
  }
}

resource blob 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: st
  name: 'default'
}

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blob
  name: 'data'
}

output stgName string = st.name
output stgId string = st.id
```

### `bicep/modules/03-network.bicep`

```bicep
// Deploy: az deployment group create -g rg-demo -f 03-network.bicep
param location string = resourceGroup().location
param vnetName string = 'vnet-demo'
param subnets array = [
  { name: 'snet-web', prefix: '10.0.1.0/24' }
  { name: 'snet-pe', prefix: '10.0.2.0/24' }
  { name: 'snet-aks', prefix: '10.0.4.0/22' }
]

resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-web'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-HTTPS-In'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '443'
        }
      }
    ]
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: { addressPrefixes: ['10.0.0.0/16'] }
    subnets: [for s in subnets: {
      name: s.name
      properties: {
        addressPrefix: s.prefix
        networkSecurityGroup: { id: nsg.id }
      }
    }]
  }
}

output vnetId string = vnet.id
output webSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-web')
output peSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-pe')
output aksSubnetId string = resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'snet-aks')
```

### `bicep/modules/04-vm.bicep`

```bicep
// Deploy: az deployment group create -g rg-demo -f 04-vm.bicep -p subnetId=<id> sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"
// VM mnemonic HOSN: Hardware, OS, Storage, Network profiles
param location string = resourceGroup().location
param vmName string = 'vm01'
param subnetId string
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string

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
    hardwareProfile: { vmSize: 'Standard_B2s' }
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
        managedDisk: { storageAccountType: 'Premium_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

output vmPrincipalId string = vm.identity.principalId
```

### `bicep/modules/05-aks.bicep`

```bicep
// Deploy: az deployment group create -g rg-demo -f 05-aks.bicep -p subnetId=<id>
param location string = resourceGroup().location
param aksName string = 'aks-demo'
param subnetId string

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
        count: 2
        vmSize: 'Standard_D4s_v5'
        osType: 'Linux'
        vnetSubnetID: subnetId
      }
    ]
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      serviceCidr: '172.16.0.0/16' // must NOT overlap the VNet
      dnsServiceIP: '172.16.0.10'
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

output aksId string = aks.id
output oidcIssuer string = aks.properties.oidcIssuerProfile.issuerURL
```

### `bicep/modules/06-rbac.bicep`

```bicep
// Deploy: az deployment group create -g rg-demo -f 06-rbac.bicep -p principalId=<objId> stgName=<name>
// Mnemonic G-R-P: Guid name, RoleDefinitionId, PrincipalId
param principalId string
param stgName string

var readerRole = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var blobContributorRole = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource st 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: stgName
}

// 1. RG scope (default scope = the deployment's RG)
resource rgReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, principalId, readerRole)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRole)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}

// 2. Resource scope
resource blobWriter 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(st.id, principalId, blobContributorRole)
  scope: st
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRole)
    principalId: principalId
    principalType: 'ServicePrincipal'
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
        actions: [
          'Microsoft.Compute/virtualMachines/read'
          'Microsoft.Compute/virtualMachines/start/action'
          'Microsoft.Compute/virtualMachines/restart/action'
        ]
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
    principalType: 'ServicePrincipal'
  }
}
```

### `bicep/modules/07-security.bicep`

```bicep
// Deploy: az deployment group create -g rg-demo -f 07-security.bicep -p vnetId=<id> peSubnetId=<id>
// Key Vault mnemonic R-S-P-N: RBAC, Soft delete, Purge protection, Network deny
param location string = resourceGroup().location
param vnetId string
param peSubnetId string
@secure()
param dbPassword string = ''

var kvSecretsUser = '4633458b-17de-408a-b874-0445c86b69e6'

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-app'
  location: location
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${uniqueString(resourceGroup().id)}'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true
    publicNetworkAccess: 'Disabled'
    networkAcls: { defaultAction: 'Deny', bypass: 'AzureServices' }
  }
}

// Written via ARM control plane, so it works even with public access disabled
resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (!empty(dbPassword)) {
  parent: kv
  name: 'db-password'
  properties: { value: dbPassword }
}

resource kvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
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

output kvName string = kv.name
output uamiPrincipalId string = uami.properties.principalId
```

### `bicep/main.bicep`

```bicep
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
```

### `bicep/main.bicepparam`

```bicep
using 'main.bicep'

param rgName = 'rg-demo'
param location = 'eastus'
param deployVm = true
param deployAks = false
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')
param dbPassword = readEnvironmentVariable('DB_PASSWORD', '')
```

---

## 4. ARM JSON

ARM = the Bicep above in JSON. Differences to say out loud: explicit `dependsOn`, functions inside `"[ ]"`, loops via `copy`/`copyIndex()`, child names as `parent/child`, extension resources use `"scope"`.

### `arm/rg.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2018-05-01/subscriptionDeploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "rgName": { "type": "string", "defaultValue": "rg-demo" },
    "location": { "type": "string", "defaultValue": "eastus" }
  },
  "resources": [
    {
      "type": "Microsoft.Resources/resourceGroups",
      "apiVersion": "2024-03-01",
      "name": "[parameters('rgName')]",
      "location": "[parameters('location')]",
      "tags": { "env": "dev" }
    }
  ],
  "outputs": {
    "rgId": { "type": "string", "value": "[subscriptionResourceId('Microsoft.Resources/resourceGroups', parameters('rgName'))]" }
  }
}
```

### `arm/storage.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "type": "string", "defaultValue": "[resourceGroup().location]" },
    "stgName": { "type": "string", "defaultValue": "[concat('st', uniqueString(resourceGroup().id))]", "minLength": 3, "maxLength": 24 }
  },
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-05-01",
      "name": "[parameters('stgName')]",
      "location": "[parameters('location')]",
      "sku": { "name": "Standard_LRS" },
      "kind": "StorageV2",
      "properties": {
        "minimumTlsVersion": "TLS1_2",
        "supportsHttpsTrafficOnly": true,
        "allowBlobPublicAccess": false
      }
    },
    {
      "type": "Microsoft.Storage/storageAccounts/blobServices/containers",
      "apiVersion": "2023-05-01",
      "name": "[concat(parameters('stgName'), '/default/data')]",
      "dependsOn": [ "[resourceId('Microsoft.Storage/storageAccounts', parameters('stgName'))]" ]
    }
  ],
  "outputs": {
    "stgId": { "type": "string", "value": "[resourceId('Microsoft.Storage/storageAccounts', parameters('stgName'))]" }
  }
}
```

### `arm/storage.parameters.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "stgName": { "value": "stdemo12345" }
  }
}
```

### `arm/network.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "type": "string", "defaultValue": "[resourceGroup().location]" },
    "vnetName": { "type": "string", "defaultValue": "vnet-demo" },
    "subnets": {
      "type": "array",
      "defaultValue": [
        { "name": "snet-web", "prefix": "10.0.1.0/24" },
        { "name": "snet-pe", "prefix": "10.0.2.0/24" }
      ]
    }
  },
  "variables": {
    "nsgId": "[resourceId('Microsoft.Network/networkSecurityGroups', 'nsg-web')]"
  },
  "resources": [
    {
      "type": "Microsoft.Network/networkSecurityGroups",
      "apiVersion": "2024-05-01",
      "name": "nsg-web",
      "location": "[parameters('location')]",
      "properties": {
        "securityRules": [
          {
            "name": "Allow-HTTPS-In",
            "properties": {
              "priority": 100,
              "direction": "Inbound",
              "access": "Allow",
              "protocol": "Tcp",
              "sourceAddressPrefix": "*",
              "sourcePortRange": "*",
              "destinationAddressPrefix": "*",
              "destinationPortRange": "443"
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Network/virtualNetworks",
      "apiVersion": "2024-05-01",
      "name": "[parameters('vnetName')]",
      "location": "[parameters('location')]",
      "dependsOn": [ "[variables('nsgId')]" ],
      "properties": {
        "addressSpace": { "addressPrefixes": [ "10.0.0.0/16" ] },
        "copy": [
          {
            "name": "subnets",
            "count": "[length(parameters('subnets'))]",
            "input": {
              "name": "[parameters('subnets')[copyIndex('subnets')].name]",
              "properties": {
                "addressPrefix": "[parameters('subnets')[copyIndex('subnets')].prefix]",
                "networkSecurityGroup": { "id": "[variables('nsgId')]" }
              }
            }
          }
        ]
      }
    }
  ],
  "outputs": {
    "webSubnetId": { "type": "string", "value": "[resourceId('Microsoft.Network/virtualNetworks/subnets', parameters('vnetName'), 'snet-web')]" }
  }
}
```

### `arm/vm.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "type": "string", "defaultValue": "[resourceGroup().location]" },
    "vmName": { "type": "string", "defaultValue": "vm01" },
    "subnetId": { "type": "string" },
    "adminUsername": { "type": "string", "defaultValue": "azureuser" },
    "sshPublicKey": { "type": "securestring" }
  },
  "variables": {
    "nicName": "[concat('nic-', parameters('vmName'))]"
  },
  "resources": [
    {
      "type": "Microsoft.Network/networkInterfaces",
      "apiVersion": "2024-05-01",
      "name": "[variables('nicName')]",
      "location": "[parameters('location')]",
      "properties": {
        "ipConfigurations": [
          {
            "name": "ipconfig1",
            "properties": {
              "privateIPAllocationMethod": "Dynamic",
              "subnet": { "id": "[parameters('subnetId')]" }
            }
          }
        ]
      }
    },
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2024-07-01",
      "name": "[parameters('vmName')]",
      "location": "[parameters('location')]",
      "dependsOn": [ "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]" ],
      "identity": { "type": "SystemAssigned" },
      "properties": {
        "hardwareProfile": { "vmSize": "Standard_B2s" },
        "osProfile": {
          "computerName": "[parameters('vmName')]",
          "adminUsername": "[parameters('adminUsername')]",
          "linuxConfiguration": {
            "disablePasswordAuthentication": true,
            "ssh": {
              "publicKeys": [
                {
                  "path": "[concat('/home/', parameters('adminUsername'), '/.ssh/authorized_keys')]",
                  "keyData": "[parameters('sshPublicKey')]"
                }
              ]
            }
          }
        },
        "storageProfile": {
          "imageReference": { "publisher": "Canonical", "offer": "ubuntu-24_04-lts", "sku": "server", "version": "latest" },
          "osDisk": { "createOption": "FromImage", "managedDisk": { "storageAccountType": "Premium_LRS" } }
        },
        "networkProfile": {
          "networkInterfaces": [ { "id": "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]" } ]
        }
      }
    }
  ],
  "outputs": {
    "principalId": { "type": "string", "value": "[reference(resourceId('Microsoft.Compute/virtualMachines', parameters('vmName')), '2024-07-01', 'full').identity.principalId]" }
  }
}
```

### `arm/vm.parameters.kvref.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "subnetId": { "value": "/subscriptions/<sub-id>/resourceGroups/rg-demo/providers/Microsoft.Network/virtualNetworks/vnet-demo/subnets/snet-web" },
    "sshPublicKey": {
      "reference": {
        "keyVault": { "id": "/subscriptions/<sub-id>/resourceGroups/rg-sec/providers/Microsoft.KeyVault/vaults/kv-prod" },
        "secretName": "vm-ssh-public-key"
      }
    }
  }
}
```

### `arm/rbac.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "principalId": { "type": "string" },
    "stgName": { "type": "string" }
  },
  "variables": {
    "readerRole": "acdd72a7-3385-48ef-bd42-f606fba81ae7",
    "blobContributorRole": "ba92f5b4-2d11-453d-a403-e96b0029c9fe",
    "stgId": "[resourceId('Microsoft.Storage/storageAccounts', parameters('stgName'))]"
  },
  "resources": [
    {
      "type": "Microsoft.Authorization/roleAssignments",
      "apiVersion": "2022-04-01",
      "name": "[guid(resourceGroup().id, parameters('principalId'), variables('readerRole'))]",
      "properties": {
        "roleDefinitionId": "[subscriptionResourceId('Microsoft.Authorization/roleDefinitions', variables('readerRole'))]",
        "principalId": "[parameters('principalId')]",
        "principalType": "ServicePrincipal"
      }
    },
    {
      "type": "Microsoft.Authorization/roleAssignments",
      "apiVersion": "2022-04-01",
      "scope": "[format('Microsoft.Storage/storageAccounts/{0}', parameters('stgName'))]",
      "name": "[guid(variables('stgId'), parameters('principalId'), variables('blobContributorRole'))]",
      "properties": {
        "roleDefinitionId": "[subscriptionResourceId('Microsoft.Authorization/roleDefinitions', variables('blobContributorRole'))]",
        "principalId": "[parameters('principalId')]",
        "principalType": "ServicePrincipal"
      }
    }
  ]
}
```

### `arm/keyvault.json`

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "type": "string", "defaultValue": "[resourceGroup().location]" },
    "kvName": { "type": "string", "defaultValue": "[concat('kv-', uniqueString(resourceGroup().id))]" },
    "dbPassword": { "type": "securestring" }
  },
  "variables": {
    "kvSecretsUser": "4633458b-17de-408a-b874-0445c86b69e6",
    "uamiId": "[resourceId('Microsoft.ManagedIdentity/userAssignedIdentities', 'id-app')]",
    "kvId": "[resourceId('Microsoft.KeyVault/vaults', parameters('kvName'))]"
  },
  "resources": [
    {
      "type": "Microsoft.ManagedIdentity/userAssignedIdentities",
      "apiVersion": "2023-01-31",
      "name": "id-app",
      "location": "[parameters('location')]"
    },
    {
      "type": "Microsoft.KeyVault/vaults",
      "apiVersion": "2023-07-01",
      "name": "[parameters('kvName')]",
      "location": "[parameters('location')]",
      "properties": {
        "tenantId": "[subscription().tenantId]",
        "sku": { "family": "A", "name": "standard" },
        "enableRbacAuthorization": true,
        "enableSoftDelete": true,
        "softDeleteRetentionInDays": 90,
        "enablePurgeProtection": true,
        "publicNetworkAccess": "Disabled",
        "networkAcls": { "defaultAction": "Deny", "bypass": "AzureServices" }
      }
    },
    {
      "type": "Microsoft.KeyVault/vaults/secrets",
      "apiVersion": "2023-07-01",
      "name": "[concat(parameters('kvName'), '/db-password')]",
      "dependsOn": [ "[variables('kvId')]" ],
      "properties": { "value": "[parameters('dbPassword')]" }
    },
    {
      "type": "Microsoft.Authorization/roleAssignments",
      "apiVersion": "2022-04-01",
      "scope": "[format('Microsoft.KeyVault/vaults/{0}', parameters('kvName'))]",
      "name": "[guid(variables('kvId'), variables('uamiId'), variables('kvSecretsUser'))]",
      "dependsOn": [ "[variables('kvId')]", "[variables('uamiId')]" ],
      "properties": {
        "roleDefinitionId": "[subscriptionResourceId('Microsoft.Authorization/roleDefinitions', variables('kvSecretsUser'))]",
        "principalId": "[reference(variables('uamiId'), '2023-01-31').principalId]",
        "principalType": "ServicePrincipal"
      }
    }
  ]
}
```

---

## 5. Azure CLI

### `cli/01-direct-create.sh`

```bash
#!/usr/bin/env bash
# DIRECT creation (no template). Pattern: az <noun> [<sub>] <verb> -g -n -l --flags ; capture: --query id -o tsv
set -euo pipefail

SUB_ID="<subscription-id>"
RG=rg-demo
LOC=eastus
SFX=$RANDOM
az account set --subscription "$SUB_ID"

# ---------- Resource group ----------
az group create -n $RG -l $LOC --tags env=dev

# ---------- Storage ----------
STG="stdemo$SFX"
az storage account create -g $RG -n $STG -l $LOC \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false
az storage container create --account-name $STG -n data --auth-mode login
STG_ID=$(az storage account show -g $RG -n $STG --query id -o tsv)

# ---------- Networking ----------
az network nsg create -g $RG -n nsg-web
az network nsg rule create -g $RG --nsg-name nsg-web -n Allow-HTTPS-In \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --destination-port-ranges 443

az network vnet create -g $RG -n vnet-demo --address-prefixes 10.0.0.0/16 \
  --subnet-name snet-web --subnet-prefixes 10.0.1.0/24 --network-security-group nsg-web
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-pe  --address-prefixes 10.0.2.0/24
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-aks --address-prefixes 10.0.4.0/22

VNET_ID=$(az network vnet show -g $RG -n vnet-demo --query id -o tsv)
WEB_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name vnet-demo -n snet-web --query id -o tsv)
AKS_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name vnet-demo -n snet-aks --query id -o tsv)

# Peering (needs both directions)
# az network vnet peering create -g $RG -n demo-to-hub --vnet-name vnet-demo --remote-vnet "$HUB_VNET_ID" --allow-vnet-access --allow-forwarded-traffic

# ---------- Compute: VM ----------
az vm create -g $RG -n vm01 --image Ubuntu2404 --size Standard_B2s \
  --admin-username azureuser --generate-ssh-keys \
  --subnet "$WEB_SUBNET_ID" --public-ip-address "" --nsg "" \
  --assign-identity
VM_PRINCIPAL=$(az vm show -g $RG -n vm01 --query identity.principalId -o tsv)

# ---------- Compute: AKS ----------
az aks create -g $RG -n aks-demo --node-count 2 --node-vm-size Standard_D4s_v5 \
  --network-plugin azure --network-policy azure --vnet-subnet-id "$AKS_SUBNET_ID" \
  --service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10 \
  --enable-managed-identity --enable-aad --enable-azure-rbac \
  --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys
az aks get-credentials -g $RG -n aks-demo

# ---------- Security: identity + Key Vault + private endpoint ----------
az identity create -g $RG -n id-app
UAMI_PID=$(az identity show -g $RG -n id-app --query principalId -o tsv)

KV="kv-demo-$SFX"
az keyvault create -g $RG -n $KV -l $LOC \
  --enable-rbac-authorization true --enable-purge-protection true --retention-days 90
KV_ID=$(az keyvault show -n $KV --query id -o tsv)

ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Key Vault Secrets Officer" --scope "$KV_ID"
az keyvault secret set --vault-name $KV -n db-password --value "$(openssl rand -base64 24)"

# lock down AFTER seeding secret (data plane needs network access)
az keyvault update -n $KV --public-network-access Disabled --default-action Deny --bypass AzureServices

az network private-endpoint create -g $RG -n pe-kv --vnet-name vnet-demo --subnet snet-pe \
  --private-connection-resource-id "$KV_ID" --group-id vault --connection-name psc-kv
az network private-dns zone create -g $RG -n privatelink.vaultcore.azure.net
az network private-dns link vnet create -g $RG -n link-vnet \
  --zone-name privatelink.vaultcore.azure.net --virtual-network "$VNET_ID" --registration-enabled false
az network private-endpoint dns-zone-group create -g $RG --endpoint-name pe-kv -n default \
  --private-dns-zone privatelink.vaultcore.azure.net --zone-name kv

# ---------- RBAC ----------
az role assignment create --assignee-object-id "$UAMI_PID" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KV_ID"
az role assignment create --assignee-object-id "$UAMI_PID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$STG_ID"
az role assignment create --assignee-object-id "$VM_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role Reader --scope "/subscriptions/$SUB_ID/resourceGroups/$RG"

cat > /tmp/vm-operator.json <<JSON
{
  "Name": "VM Operator ($RG)",
  "Description": "Read, start and restart VMs",
  "Actions": [
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/restart/action"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/$SUB_ID/resourceGroups/$RG"]
}
JSON
az role definition create --role-definition @/tmp/vm-operator.json
az role assignment list --assignee "$UAMI_PID" --all -o table

# ---------- Governance: Azure Policy (built-in "Allowed locations") ----------
az policy assignment create -n allowed-locations \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG" \
  --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
  --params '{"listOfAllowedLocations":{"value":["eastus","westeurope"]}}'
```

### `cli/02-deploy-templates.sh`

```bash
#!/usr/bin/env bash
# TEMPLATE deployment. Rule: file scope == command scope (group | sub | mg | tenant)
set -euo pipefail
RG=rg-demo; LOC=eastus

# ---- Bicep ----
az deployment sub create   -l $LOC -f ../bicep/modules/01-rg.bicep -p rgName=$RG       # targetScope='subscription'
az deployment group create -g $RG  -f ../bicep/modules/02-storage.bicep                # default scope = RG
az deployment group what-if -g $RG -f ../bicep/modules/03-network.bicep                # preview
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
az deployment sub create   -l $LOC -f ../bicep/main.bicep -p ../bicep/main.bicepparam  # everything

# ---- ARM JSON (same commands, .json file) ----
az deployment sub create   -l $LOC -f ../arm/rg.json -p rgName=$RG
az deployment group create -g $RG  -f ../arm/storage.json -p @../arm/storage.parameters.json
az deployment group create -g $RG  -f ../arm/network.json --mode Incremental

# ---- Convert ----
az bicep build     -f ../bicep/main.bicep            # Bicep -> ARM JSON
az bicep decompile -f ../arm/network.json            # ARM JSON -> Bicep (best effort)

# ---- Lifecycle with deployment stacks (manages deletes) ----
az stack group create -n stack-demo -g $RG -f ../bicep/modules/02-storage.bicep \
  --action-on-unmanage deleteResources --deny-settings-mode denyDelete

# ---- Inspect / troubleshoot ----
az deployment group list -g $RG -o table
az deployment operation group list -g $RG -n storage --query "[?properties.provisioningState=='Failed']"
```

---

## 6. Terraform

The ARM → TF rule: nested `properties` become flat arguments or nested blocks; the RG is an argument (`resource_group_name`); dependencies are implicit through references.

### `terraform/providers.tf`

```hcl
terraform {
  required_version = ">= 1.6"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.0" }
    random  = { source = "hashicorp/random", version = "~> 3.6" }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate001"
    container_name       = "tfstate"
    key                  = "demo.terraform.tfstate"
    use_oidc             = true
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
  subscription_id = var.subscription_id # mandatory in azurerm 4.x
}

data "azurerm_client_config" "current" {}
```

### `terraform/variables.tf`

```hcl
variable "subscription_id" {
  type = string
}

variable "env" {
  type    = string
  default = "dev"
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env must be dev or prod."
  }
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "subnets" {
  type = map(string)
  default = {
    web = "10.0.1.0/24"
    pe  = "10.0.2.0/24"
    aks = "10.0.4.0/22"
  }
}

variable "nsg_rules" {
  type = list(object({ name = string, priority = number, port = string }))
  default = [
    { name = "Allow-HTTPS-In", priority = 100, port = "443" },
  ]
}

variable "deploy_vm" {
  type    = bool
  default = true
}

variable "deploy_aks" {
  type    = bool
  default = false
}

variable "ssh_public_key" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}
```

### `terraform/main.tf`

```hcl
# ---------- Resource group + storage ----------
resource "random_string" "sfx" {
  length  = 6
  special = false
  upper   = false
}

locals {
  name = "demo-${var.env}"
  tags = { env = var.env, managed_by = "terraform" }
}

resource "azurerm_resource_group" "rg" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "stg" {
  name                            = "st${var.env}${random_string.sfx.result}"
  resource_group_name             = azurerm_resource_group.rg.name
  location                        = azurerm_resource_group.rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

resource "azurerm_storage_container" "data" {
  name                  = "data"
  storage_account_id    = azurerm_storage_account.stg.id
  container_access_type = "private"
}
```

### `terraform/network.tf`

```hcl
resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  dynamic "security_rule" {
    for_each = var.nsg_rules
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = security_rule.value.port
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${local.name}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "snet" {
  for_each             = var.subnets
  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value]
}

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.snet["web"].id
  network_security_group_id = azurerm_network_security_group.web.id
}
```

### `terraform/compute.tf`

```hcl
# ---------- VM (HOSN -> size / admin_* / os_disk+image / nic) ----------
resource "azurerm_network_interface" "vm" {
  count               = var.deploy_vm ? 1 : 0
  name                = "nic-vm01"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.snet["web"].id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  count                 = var.deploy_vm ? 1 : 0
  name                  = "vm01"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B2s"
  admin_username        = "azureuser"
  network_interface_ids = [azurerm_network_interface.vm[0].id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# ---------- AKS ----------
resource "azurerm_kubernetes_cluster" "aks" {
  count                     = var.deploy_aks ? 1 : 0
  name                      = "aks-${local.name}"
  location                  = azurerm_resource_group.rg.location
  resource_group_name       = azurerm_resource_group.rg.name
  dns_prefix                = "aks${var.env}"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  default_node_pool {
    name           = "system"
    node_count     = 2
    vm_size        = "Standard_D4s_v5"
    vnet_subnet_id = azurerm_subnet.snet["aks"].id
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }

  azure_active_directory_role_based_access_control {
    azure_rbac_enabled = true
    tenant_id          = data.azurerm_client_config.current.tenant_id
  }
}
```

### `terraform/rbac.tf`

```hcl
# G-R-P -> TF generates the GUID; you give scope + role + principal
resource "azurerm_role_assignment" "deployer_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "app_kv" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "app_blob" {
  scope                = azurerm_storage_account.stg.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "vm_reader" {
  count                = var.deploy_vm ? 1 : 0
  scope                = azurerm_resource_group.rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_linux_virtual_machine.vm[0].identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "vm_operator" {
  name  = "VM Operator (${azurerm_resource_group.rg.name})"
  scope = azurerm_resource_group.rg.id

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
    ]
    not_actions = []
  }

  assignable_scopes = [azurerm_resource_group.rg.id]
}

resource "azurerm_role_assignment" "app_vm_operator" {
  scope              = azurerm_resource_group.rg.id
  role_definition_id = azurerm_role_definition.vm_operator.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.app.principal_id
  principal_type     = "ServicePrincipal"
}
```

### `terraform/security.tf`

```hcl
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-app"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

# R-S-P-N: RBAC, Soft delete, Purge protection, Network deny
resource "azurerm_key_vault" "kv" {
  name                          = "kv-${var.env}-${random_string.sfx.result}"
  location                      = azurerm_resource_group.rg.location
  resource_group_name           = azurerm_resource_group.rg.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  enable_rbac_authorization     = true # newer 4.x name: rbac_authorization_enabled
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  public_network_access_enabled = false

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# Data-plane write: runner must reach the vault (self-hosted agent in VNet, or allow its IP)
resource "azurerm_key_vault_secret" "db" {
  name         = "db-password"
  value        = var.db_password
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [azurerm_role_assignment.deployer_kv, azurerm_private_endpoint.kv]
}

resource "azurerm_private_dns_zone" "kv" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_private_dns_zone_virtual_network_link" "kv" {
  name                  = "link-vnet"
  resource_group_name   = azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.kv.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
}

resource "azurerm_private_endpoint" "kv" {
  name                = "pe-kv"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  subnet_id           = azurerm_subnet.snet["pe"].id

  private_service_connection {
    name                           = "psc-kv"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.kv.id]
  }
}

# Governance: built-in "Allowed locations"
resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  resource_group_id    = azurerm_resource_group.rg.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/e56962a6-4747-49cd-b67b-bf8b01975c4c"
  parameters = jsonencode({
    listOfAllowedLocations = { value = ["eastus", "westeurope"] }
  })
}
```

### `terraform/outputs.tf`

```hcl
output "rg_name" {
  value = azurerm_resource_group.rg.name
}

output "key_vault_uri" {
  value = azurerm_key_vault.kv.vault_uri
}

output "subnet_ids" {
  value = { for k, s in azurerm_subnet.snet : k => s.id }
}

output "aks_oidc_issuer" {
  value = var.deploy_aks ? azurerm_kubernetes_cluster.aks[0].oidc_issuer_url : null
}
```

### `terraform/terraform.tfvars.example`

```hcl
subscription_id = "<subscription-id>"
env             = "dev"
location        = "eastus"
deploy_vm       = true
deploy_aks      = false
# pass secrets via env: TF_VAR_ssh_public_key, TF_VAR_db_password
```

### `terraform/commands.md`

```bash
terraform init -backend-config="key=dev.tfstate"
terraform fmt -recursive -check
terraform validate
terraform plan -var-file=dev.tfvars -out=tfplan
terraform plan -detailed-exitcode        # 0 none, 1 error, 2 changes
terraform apply tfplan
terraform state list | show <addr> | mv <a> <b> | rm <addr>
terraform import azurerm_resource_group.rg /subscriptions/<sub>/resourceGroups/rg-demo-dev
terraform plan -generate-config-out=generated.tf   # with import {} blocks
terraform force-unlock <lock-id>
terraform workspace new prod && terraform workspace select prod
```

---

## 7. Azure DevOps YAML pipelines

One pipeline, two templates per tool. Queue `azure-pipelines.yml`, pick **bicep** or **terraform**, and (for Bicep) the main file or a single module.

```
pipelines/
├── azure-pipelines.yml          entry point: parameters tool + bicepTarget
├── templates/
│   ├── bicep-validate.yml       Gate 1: build + lint, publish artifact
│   ├── bicep-deploy.yml         per env: validate + what-if -> approval -> create  (calls bicep/deploy.sh)
│   ├── terraform-validate.yml   Gate 1: fmt + validate, no backend
│   └── terraform-deploy.yml     per env: plan -> approval -> apply saved plan
└── examples/                    syntax reference only, not wired to anything
```

| | Bicep | Terraform |
|---|---|---|
| Validate (no Azure) | `bicep-validate.yml` | `terraform-validate.yml` |
| Preview | `deploy.sh validate` + `what-if` | `terraform plan -detailed-exitcode` |
| Approval | ADO environment `<env>` | ADO environment `<env>` |
| Deploy | `deploy.sh create <target>` | `terraform apply tfplan` |
| Per env | `sc-azure-<env>`, `vg-iac-<env>` | `sc-azure-<env>`, `vg-iac-<env>`, state key `<env>.tfstate` |

Output-variable lookup: same stage `dependencies.<Job>.outputs['<step>.<var>']` · other stage `stageDependencies.<Stage>.<Job>.outputs['<step>.<var>']` · stage condition `dependencies.<Stage>.outputs['<Job>.<step>.<var>']` · deployment jobs repeat the job name: `outputs['<DeployJob>.<step>.<var>']`.

### `pipelines/azure-pipelines.yml`

```yaml
# The ONE pipeline for this kit. Pick a tool when you queue a run; each side is validate -> dev -> prod.
#
#   tool: bicep      bicep-validate.yml    -> bicep-deploy.yml     (dev, prod)   calls kit/bicep/deploy.sh <action> <target>
#   tool: terraform  terraform-validate.yml -> terraform-deploy.yml (dev, prod)   plan -> approval -> apply
#
# Prod runs only from main. PRs stop at what-if / plan.
# One-time ADO setup per environment <env> in (dev, prod):
#   service connection sc-azure-<env>  (ARM, workload identity federation)
#   variable group     vg-iac-<env>    RG, SSH_PUBLIC_KEY, DB_PASSWORD (secret), EXTRA_PARAMS (optional, Bicep)
#   environment        <env>           add approvals on prod
parameters:
- name: tool
  displayName: IaC tool
  type: string
  default: bicep
  values: [bicep, terraform]
- name: bicepTarget
  displayName: Bicep target (main files or a single module)
  type: string
  default: main-rg
  values:
  - main-rg        # all modules into the existing RG (RG-scoped SPN)
  - main           # creates the RG too (needs subscription rights)
  - storage
  - network
  - vm             # needs network
  - aks            # needs network
  - security       # needs network
  - rbac           # needs security + storage
  - mini

trigger:
  branches:
    include: [main]
  paths:
    include: [kit/bicep/*, kit/pipelines/*]   # CI uses the defaults: bicep / main-rg

pr:
  branches:
    include: [main]
  paths:
    include: [kit/bicep/*, kit/pipelines/*]      # queue terraform runs manually (tool: terraform)

stages:
- ${{ if eq(parameters.tool, 'bicep') }}:
  - template: templates/bicep-validate.yml
  - template: templates/bicep-deploy.yml
    parameters:
      environment: dev
      target: ${{ parameters.bicepTarget }}
  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/main') }}:
    - template: templates/bicep-deploy.yml
      parameters:
        environment: prod
        target: ${{ parameters.bicepTarget }}
        dependsOn: [bicep_dev]

- ${{ if eq(parameters.tool, 'terraform') }}:
  - template: templates/terraform-validate.yml
  - template: templates/terraform-deploy.yml
    parameters:
      environment: dev
  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/main') }}:
    - template: templates/terraform-deploy.yml
      parameters:
        environment: prod
        dependsOn: [terraform_dev]
```

### `pipelines/templates/bicep-validate.yml`

```yaml
# Bicep Gate 1: compile + lint every file (no Azure call), then publish kit/bicep as artifact `bicep`
# so every environment deploys exactly the files that passed here.
stages:
- stage: bicep_validate
  displayName: Bicep validate
  jobs:
  - job: build
    displayName: Build + lint
    pool:
      vmImage: ubuntu-latest
    steps:
    - checkout: self
    - bash: |
        set -euo pipefail
        az bicep install                  # no-op when the agent already has it
        for f in modules/*.bicep main.bicep main-rg.bicep; do
          az bicep build -f "$f" --stdout >/dev/null && echo "OK  $f"
        done
        az bicep lint -f main.bicep
        az bicep lint -f main-rg.bicep
      displayName: Gate 1 build + lint
      workingDirectory: kit/bicep
    - task: CopyFiles@2
      displayName: Stage deployable files
      inputs:
        SourceFolder: kit/bicep
        Contents: |
          *.bicep
          *.bicepparam
          deploy.sh
          modules/*.bicep
        TargetFolder: $(Build.ArtifactStagingDirectory)/bicep
    - publish: $(Build.ArtifactStagingDirectory)/bicep
      artifact: bicep
```

### `pipelines/templates/bicep-deploy.yml`

```yaml
# Bicep deploy for one environment: Gate 2 validate + Gate 3 what-if -> approval -> Gate 4 create
# Every step calls kit/bicep/deploy.sh, the same script you run locally, so pipeline and laptop behave the same.
#
# Per-environment names follow one convention:
#   service connection sc-azure-<env> | variable group vg-iac-<env> | ADO environment <env>
# Variable group holds: RG, SSH_PUBLIC_KEY, DB_PASSWORD (secret), EXTRA_PARAMS (optional, e.g. deployVm=false)
parameters:
- name: environment
  type: string
- name: target                       # main-rg | main | storage | network | vm | aks | security | rbac | mini
  type: string
- name: dependsOn
  type: object
  default: [bicep_validate]

stages:
- stage: bicep_${{ parameters.environment }}
  displayName: Bicep ${{ parameters.environment }} (${{ parameters.target }})
  dependsOn: ${{ parameters.dependsOn }}
  variables:
  - name: EXTRA_PARAMS               # default; the variable group overrides it when set
    value: ''
  - group: vg-iac-${{ parameters.environment }}
  jobs:
  - job: preview
    displayName: Validate + what-if
    pool:
      vmImage: ubuntu-latest
    steps:
    - checkout: none
    - download: current
      artifact: bicep
    - task: AzureCLI@2
      displayName: deploy.sh validate + what-if
      env:                           # secrets reach scripts only through env:
        RG: $(RG)
        SSH_PUBLIC_KEY: $(SSH_PUBLIC_KEY)
        DB_PASSWORD: $(DB_PASSWORD)
        EXTRA_PARAMS: $(EXTRA_PARAMS)
      inputs:
        azureSubscription: sc-azure-${{ parameters.environment }}
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          set -euo pipefail
          sh=$(Pipeline.Workspace)/bicep/deploy.sh; chmod +x "$sh"
          "$sh" validate ${{ parameters.target }}
          "$sh" what-if  ${{ parameters.target }}

  - deployment: deploy
    displayName: Deploy
    dependsOn: preview
    condition: and(succeeded(), ne(variables['Build.Reason'], 'PullRequest'))   # PRs stop at what-if
    environment: ${{ parameters.environment }}                                   # approvals live here
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: bicep
          - task: AzureCLI@2
            displayName: deploy.sh create
            env:
              RG: $(RG)
              SSH_PUBLIC_KEY: $(SSH_PUBLIC_KEY)
              DB_PASSWORD: $(DB_PASSWORD)
              EXTRA_PARAMS: $(EXTRA_PARAMS)
            inputs:
              azureSubscription: sc-azure-${{ parameters.environment }}
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                set -euo pipefail
                sh=$(Pipeline.Workspace)/bicep/deploy.sh; chmod +x "$sh"
                "$sh" create ${{ parameters.target }}
```

### `pipelines/templates/terraform-validate.yml`

```yaml
# Terraform Gate 1: fmt + validate with no backend and no Azure call (mirror of bicep-validate.yml)
stages:
- stage: terraform_validate
  displayName: Terraform validate
  jobs:
  - job: validate
    displayName: fmt + validate
    pool:
      vmImage: ubuntu-latest
    steps:
    - checkout: self
    - bash: |
        set -euo pipefail
        terraform version
        terraform fmt -check -recursive
        terraform init -backend=false -input=false
        terraform validate
      displayName: Gate 1 fmt + validate
      workingDirectory: kit/terraform
```

### `pipelines/templates/terraform-deploy.yml`

```yaml
# Terraform deploy for one environment: plan -> approval -> apply the SAME saved plan (mirror of bicep-deploy.yml)
# Same naming convention as Bicep: sc-azure-<env> | vg-iac-<env> | ADO environment <env>
# Variable group holds: SSH_PUBLIC_KEY, DB_PASSWORD (secret). terraform.tfvars is git-ignored, so inputs come in as TF_VAR_*.
# State: backend in providers.tf, one key per environment (<env>.tfstate). Apply is skipped when the plan has no changes.
parameters:
- name: environment
  type: string
- name: dependsOn
  type: object
  default: [terraform_validate]

stages:
- stage: terraform_${{ parameters.environment }}
  displayName: Terraform ${{ parameters.environment }}
  dependsOn: ${{ parameters.dependsOn }}
  variables:
  - group: vg-iac-${{ parameters.environment }}
  jobs:
  - job: plan
    displayName: Plan
    pool:
      vmImage: ubuntu-latest
    steps:
    - checkout: self
    - task: AzureCLI@2
      name: planStep
      displayName: terraform plan
      env:
        TF_VAR_env: ${{ parameters.environment }}
        TF_VAR_ssh_public_key: $(SSH_PUBLIC_KEY)
        TF_VAR_db_password: $(DB_PASSWORD)
      inputs:
        azureSubscription: sc-azure-${{ parameters.environment }}
        scriptType: bash
        scriptLocation: inlineScript
        addSpnToEnvironment: true          # exposes servicePrincipalId / tenantId / idToken for OIDC
        workingDirectory: kit/terraform
        inlineScript: |
          set -euo pipefail
          export ARM_CLIENT_ID=$servicePrincipalId ARM_TENANT_ID=$tenantId ARM_OIDC_TOKEN=$idToken ARM_USE_OIDC=true
          export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv) TF_VAR_subscription_id=$(az account show --query id -o tsv)
          terraform init -input=false -backend-config="key=${{ parameters.environment }}.tfstate"
          rc=0; terraform plan -input=false -detailed-exitcode -out=tfplan || rc=$?   # 0 none, 1 error, 2 changes
          [ "$rc" -eq 1 ] && exit 1
          echo "##vso[task.setvariable variable=hasChanges;isOutput=true]$([ "$rc" -eq 2 ] && echo true || echo false)"
          mkdir -p "$(Build.ArtifactStagingDirectory)/tfplan"
          cp tfplan .terraform.lock.hcl "$(Build.ArtifactStagingDirectory)/tfplan/"   # apply must use the same provider versions
    - publish: $(Build.ArtifactStagingDirectory)/tfplan
      artifact: tfplan_${{ parameters.environment }}

  - deployment: apply
    displayName: Apply
    dependsOn: plan
    condition: >-
      and(succeeded(), ne(variables['Build.Reason'], 'PullRequest'),
          eq(dependencies.plan.outputs['planStep.hasChanges'], 'true'))
    environment: ${{ parameters.environment }}
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - checkout: self                 # deployment jobs don't auto-checkout
          - download: current
            artifact: tfplan_${{ parameters.environment }}
          - task: AzureCLI@2
            displayName: terraform apply
            inputs:
              azureSubscription: sc-azure-${{ parameters.environment }}
              scriptType: bash
              scriptLocation: inlineScript
              addSpnToEnvironment: true
              workingDirectory: kit/terraform
              inlineScript: |
                set -euo pipefail
                export ARM_CLIENT_ID=$servicePrincipalId ARM_TENANT_ID=$tenantId ARM_OIDC_TOKEN=$idToken ARM_USE_OIDC=true
                export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
                cp $(Pipeline.Workspace)/tfplan_${{ parameters.environment }}/.terraform.lock.hcl .
                terraform init -input=false -backend-config="key=${{ parameters.environment }}.tfstate"
                terraform apply -input=false $(Pipeline.Workspace)/tfplan_${{ parameters.environment }}/tfplan
```

### `bicep/deploy.sh`

Called by `bicep-deploy.yml`; run it locally the same way: `./deploy.sh what-if network`.

```bash
#!/usr/bin/env bash
# deploy.sh <action> <target> — one entry point for local runs AND the pipeline (kit/pipelines/templates/bicep-deploy.yml)
#
#   action : validate | what-if | create
#   target : main-rg   all modules into an existing RG   (main-rg.bicepparam)
#            main      RG + all modules, subscription scope (main.bicepparam)
#            storage | network | vm | aks | security | rbac | mini   one module (README Option A)
#
# Env: RG (every target except main), LOCATION (main only, default eastus),
#      SSH_PUBLIC_KEY, DB_PASSWORD (source ./modules/set-secrets.sh locally),
#      EXTRA_PARAMS (optional "name=value name=value" overrides)
#
# Single modules read their inputs from earlier deployments (vm needs network, rbac needs security + storage).
# The deployment name is the target, so cleanup.sh can find everything this script created.
set -euo pipefail
cd "$(dirname "$0")"

usage() { sed -n '2,9p' "$0" >&2; exit 2; }
action=${1:-}; target=${2:-}
case "$action" in validate|what-if|create) ;; *) usage ;; esac

# output <deployment> <name>: read an output from an earlier deployment in $RG
output() {
  az deployment group show -g "$RG" -n "$1" --query "properties.outputs.$2.value" -o tsv 2>/dev/null |
    grep . || { echo "ERROR: no output '$2' from deployment '$1' in $RG. Deploy target '$1' first." >&2; exit 1; }
}

module=''; params=()
case "$target" in
  main-rg)  src=(-p main-rg.bicepparam) ;;
  main)     src=(-p main.bicepparam) ;;
  storage)  module=02-storage ;;
  network)  module=03-network ;;
  vm)       module=04-vm;       params=(subnetId="$(output network webSubnetId)" sshPublicKey="${SSH_PUBLIC_KEY:?}") ;;
  aks)      module=05-aks;      params=(subnetId="$(output network aksSubnetId)") ;;
  security) module=07-security; params=(vnetId="$(output network vnetId)" peSubnetId="$(output network peSubnetId)"
                                        dbPassword="${DB_PASSWORD:-}") ;;
  rbac)     module=06-rbac;     params=(principalId="$(output security uamiPrincipalId)" stgName="$(output storage stgName)") ;;
  mini)     module=mini;        params=(sshPublicKey="${SSH_PUBLIC_KEY:?}") ;;
  *)        usage ;;
esac

if [ "$target" = main ]; then
  at=(sub -l "${LOCATION:-eastus}"); show=(sub)
else
  : "${RG:?export RG=<resource group> first}"
  at=(group -g "$RG"); show=(group -g "$RG")
fi
[ -n "$module" ] && src=(-f "modules/$module.bicep")

args=("${src[@]}")
[ ${#params[@]} -gt 0 ] && args+=(-p "${params[@]}")
read -ra extra <<< "${EXTRA_PARAMS:-}"
[ ${#extra[@]} -gt 0 ] && args+=(-p "${extra[@]}")

echo "==> az deployment ${at[0]} $action  target=$target"
case "$action" in
  validate) az deployment "${at[@]}" validate -n "$target" "${args[@]}" -o none && echo "valid" ;;
  what-if)  az deployment "${at[@]}" what-if  -n "$target" "${args[@]}" ;;
  create)   az deployment "${at[@]}" create   -n "$target" "${args[@]}" -o none
            az deployment "${show[@]}" show -n "$target" --query properties.outputs -o json ;;
esac
```

### Examples (syntax reference)

Stand-alone snippets for interview questions on pipeline syntax. They are not part of the real pipeline.

### `pipelines/examples/single-job.yml`

```yaml
# Root mnemonic T-R-V-P-S: Trigger, Resources, Variables, Pool, Stages/Jobs/Steps
trigger:
  branches:
    include: [main]
  paths:
    exclude: [docs/*]

pr:
  branches:
    include: [main]

pool:
  vmImage: ubuntu-latest

variables:
  rgName: rg-demo
  location: eastus

steps:
- checkout: self

- script: az bicep build -f kit/bicep/main.bicep
  displayName: Bicep lint/build

- task: AzureCLI@2
  displayName: Deploy RG (Bicep)
  inputs:
    azureSubscription: sc-azure-dev        # ARM service connection (workload identity federation)
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: |
      az deployment sub create -l $(location) \
        -f kit/bicep/modules/01-rg.bicep -p rgName=$(rgName)
```

### `pipelines/examples/parallel-jobs-matrix.yml`

```yaml
# Jobs run in PARALLEL unless dependsOn is set
trigger: [main]

pool:
  vmImage: ubuntu-latest

jobs:
- job: BicepLint
  displayName: Bicep build
  steps:
  - script: az bicep build -f kit/bicep/main.bicep

- job: TerraformLint
  displayName: Terraform fmt/validate
  steps:
  - script: |
      cd kit/terraform
      terraform fmt -check -recursive
      terraform init -backend=false
      terraform validate

- job: ScriptTests
  strategy:
    matrix:
      py310: { pythonVersion: '3.10' }
      py312: { pythonVersion: '3.12' }
    maxParallel: 2
  steps:
  - task: UsePythonVersion@0
    inputs:
      versionSpec: $(pythonVersion)
  - script: python --version

- job: Package
  dependsOn: [BicepLint, TerraformLint, ScriptTests]   # fan-in
  condition: succeeded()
  timeoutInMinutes: 20
  steps:
  - task: CopyFiles@2
    inputs:
      Contents: |
        kit/bicep/**
        kit/terraform/**
      TargetFolder: $(Build.ArtifactStagingDirectory)
  - publish: $(Build.ArtifactStagingDirectory)
    artifact: iac
```

### `pipelines/examples/multi-stage-approvals.yml`

```yaml
# Hierarchy S-J-S: Stages -> Jobs -> Steps
# Teaching skeleton (sub scope). The real pipeline for this kit is ../azure-pipelines.yml
trigger:
  branches:
    include: [main]

variables:
- group: vg-common                 # variable group (can be Key Vault-linked)
- name: location
  value: eastus

stages:
- stage: Build
  jobs:
  - job: Build
    pool:
      vmImage: ubuntu-latest
    steps:
    - script: az bicep build -f kit/bicep/main.bicep
    - publish: $(System.DefaultWorkingDirectory)/kit/bicep
      artifact: bicep

- stage: Dev
  dependsOn: Build
  variables:
  - group: vg-dev
  jobs:
  - deployment: DeployDev
    environment: dev
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: bicep
          - task: AzureCLI@2
            inputs:
              azureSubscription: sc-azure-dev
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                az deployment sub create -l $(location) \
                  -f $(Pipeline.Workspace)/bicep/main.bicep \
                  -p $(Pipeline.Workspace)/bicep/main.bicepparam

- stage: Prod
  dependsOn: Dev
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
  jobs:
  - deployment: DeployProd
    environment: prod               # approvals & checks are configured on the environment
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - download: current
            artifact: bicep
          - task: AzureCLI@2
            inputs:
              azureSubscription: sc-azure-prod
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                az deployment sub what-if -l $(location) -f $(Pipeline.Workspace)/bicep/main.bicep \
                  -p $(Pipeline.Workspace)/bicep/main.bicepparam
                az deployment sub create  -l $(location) -f $(Pipeline.Workspace)/bicep/main.bicep \
                  -p $(Pipeline.Workspace)/bicep/main.bicepparam
```

### `pipelines/examples/cross-repo-templates.yml`

```yaml
# App/infra repo pipeline that CALLS templates from another repo and is TRIGGERED by another pipeline
resources:
  repositories:
  - repository: templates                   # alias used after '@'
    type: git                               # Azure Repos
    name: Platform/pipeline-templates       # <Project>/<Repo>
    ref: refs/tags/v1.4.0                   # pin a version
  - repository: ghTemplates
    type: github
    name: myorg/pipeline-templates
    endpoint: sc-github                     # GitHub service connection
    ref: refs/heads/main
  pipelines:
  - pipeline: upstream                      # alias
    source: infra-ci                        # upstream pipeline NAME
    project: Platform
    trigger:
      branches:
        include: [main]                     # run when infra-ci succeeds on main

trigger: none

stages:
- template: templates/terraform-deploy.yml@templates   # ../templates/terraform-deploy.yml, published to a shared repo
  parameters:
    environment: dev
    dependsOn: []

- template: templates/terraform-deploy.yml@templates
  parameters:
    environment: prod
    dependsOn: [terraform_dev]

- stage: UseUpstream
  dependsOn: []                             # runs in parallel with terraform_dev
  jobs:
  - job: fetch
    pool:
      vmImage: ubuntu-latest
    steps:
    - checkout: templates                   # check out the OTHER repo
    - download: upstream                    # artifacts from the triggering pipeline
      artifact: drop
    - script: echo "Upstream run $(resources.pipeline.upstream.runID)"
```

### `pipelines/examples/extends-governance.yml`

```yaml
# Enforced template: pair with a "Required template" check on the environment / service connection
resources:
  repositories:
  - repository: templates
    type: git
    name: Platform/pipeline-templates

extends:
  template: governance/secure-pipeline.yml@templates
  parameters:
    stages:
    - stage: Build
      jobs:
      - job: Build
        steps:
        - script: echo build
```

### `pipelines/examples/dependencies-and-outputs.yml`

```yaml
# Stage deps, job deps, step deps, output variables, fan-out/fan-in
# Expressions: ${{ }} compile | $[ ] runtime | $( ) right-before-task
trigger: none

pool:
  vmImage: ubuntu-latest

stages:
- stage: Plan
  jobs:
  - job: Detect
    steps:
    - bash: echo "##vso[task.setvariable variable=hasChanges;isOutput=true]true"
      name: setVar                          # 'name' + isOutput=true are REQUIRED

  - job: Report                             # job -> job, SAME stage
    dependsOn: Detect
    variables:
      changes: $[ dependencies.Detect.outputs['setVar.hasChanges'] ]
    steps:
    - script: echo "changes=$(changes)"

- stage: Apply                              # stage condition reads another stage's output
  dependsOn: Plan
  condition: and(succeeded(), eq(dependencies.Plan.outputs['Detect.setVar.hasChanges'], 'true'))
  jobs:
  - job: Apply
    variables:                              # job in OTHER stage
      changes: $[ stageDependencies.Plan.Detect.outputs['setVar.hasChanges'] ]
    steps:
    - script: ./deploy.sh
      name: deploy
    - script: ./smoke-test.sh
      condition: succeeded()
    - script: ./rollback.sh
      condition: failed()
    - script: ./flaky-call.sh
      continueOnError: true
      retryCountOnTaskFailure: 2
    - script: ./notify.sh
      condition: always()

# fan-out
- stage: Test_EU
  dependsOn: Apply
  jobs:
  - job: t
    steps:
    - script: echo EU
- stage: Test_US
  dependsOn: Apply
  jobs:
  - job: t
    steps:
    - script: echo US

# fan-in
- stage: Release
  dependsOn: [Test_EU, Test_US]
  condition: succeeded()
  jobs:
  - job: r
    steps:
    - script: echo release

# independent stage: starts immediately
- stage: Docs
  dependsOn: []
  jobs:
  - job: d
    steps:
    - script: echo docs
```
