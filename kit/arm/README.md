# ARM JSON Kit — Azure Landing Zone (Demo)

Hand-written ARM templates for the same resources as the [Bicep kit](../bicep/README.md). ARM JSON is what Bicep compiles to and what Azure Resource Manager actually runs,
so this folder is the "under the hood" view: same deploy commands, same validation gates, more syntax.

## Layout

| File | Scope | Creates | Outputs |
|------|-------|---------|---------|
| `rg.json` | subscription | Resource group | `rgId` |
| `storage.json` + `storage.parameters.json` | resource group | StorageV2 + `data` container | `stgId` |
| `network.json` | resource group | `nsg-web` + `vnet-demo` with `snet-web`, `snet-pe` | `webSubnetId` |
| `vm.json` | resource group | NIC + `vm01` (Ubuntu, SSH only, system-assigned MI) | `principalId` |
| `vm.parameters.kvref.json` | — | Parameter file that pulls `sshPublicKey` from Key Vault at deploy time | — |
| `keyvault.json` | resource group | UAMI + Key Vault (RBAC, private) + `db-password` secret + Secrets User role | — |
| `rbac.json` | resource group | Reader on the RG + Blob Data Contributor on one storage account | — |
| [`../arm-built/`](../arm-built) | — | ARM JSON **generated** from the Bicep modules (`az bicep build`), for comparison | — |

Every file compiles to the same kind of object ARM receives from Bicep: `$schema`, `parameters`, `variables`, `resources`, `outputs`.

---

## 1. Log in

Same service principal as the Bicep kit: [Bicep README section 1](../bicep/README.md#1-log-in-with-the-service-principal-kodekloud-playground).

```bash
cd ValueMomentum/kit/arm
source ../bicep/modules/az-login.sh      # exports RG
source ../bicep/modules/set-secrets.sh   # exports SSH_PUBLIC_KEY, DB_PASSWORD
```

---

## 2. The rule: file scope == command scope

The `$schema` line decides the command, exactly like `targetScope` in Bicep:

| `$schema` ends with | Command |
|---------------------|---------|
| `deploymentTemplate.json#` | `az deployment group create -g <rg> -f x.json` |
| `subscriptionDeploymentTemplate.json#` | `az deployment sub create -l <region> -f x.json` |
| `managementGroupDeploymentTemplate.json#` | `az deployment mg create -m <mg> -l <region> -f x.json` |
| `tenantDeploymentTemplate.json#` | `az deployment tenant create -l <region> -f x.json` |

The four validation gates from the [Bicep README section 3](../bicep/README.md#3-validation--the-core-idea) apply unchanged, except Gate 1:
there is no compiler, so a JSON typo surfaces at Gate 2 (`validate`) instead of on your machine.

---

## 3. Deploy, file by file

Each step is **validate → what-if → create**. Outputs of one step feed the next.

```bash
# 1. Resource group (subscription scope; skip on KodeKloud, the lab RG already exists)
az deployment sub create -l eastus -f rg.json -p rgName=rg-demo

# 2. Storage (the parameter file pins stgName; pass your own to avoid a global name clash)
az deployment group validate -g "$RG" -f storage.json -p @storage.parameters.json -o none && echo valid
az deployment group create   -g "$RG" -f storage.json -p stgName="st$RANDOM$RANDOM" -n storage -o table
STG=$(az deployment group show -g "$RG" -n storage --query properties.outputs.stgId.value -o tsv | xargs basename)

# 3. Network
az deployment group what-if -g "$RG" -f network.json
az deployment group create  -g "$RG" -f network.json -n network -o table
WEB=$(az deployment group show -g "$RG" -n network --query properties.outputs.webSubnetId.value -o tsv)

# 4. VM
az deployment group create -g "$RG" -f vm.json -n vm -p subnetId="$WEB" sshPublicKey="$SSH_PUBLIC_KEY" -o table

# 5. Key Vault + identity + secret (see playground notes first)
az deployment group create -g "$RG" -f keyvault.json -n keyvault -p dbPassword="$DB_PASSWORD" -o table

# 6. RBAC (needs Owner / User Access Administrator)
PID=$(az deployment group show -g "$RG" -n vm --query properties.outputs.principalId.value -o tsv)
az deployment group create -g "$RG" -f rbac.json -n rbac -p principalId="$PID" stgName="$STG" -o table
```

### Parameter files and Key Vault references

`-p @file.json` loads a parameter file; `-p name=value` after it overrides single values.
`vm.parameters.kvref.json` shows the pattern for secrets: instead of a `value`, the parameter holds a `reference` to a Key Vault secret, and ARM reads it during deployment.
The secret never appears on the command line or in deployment history. For that to work:

- the referenced vault must have `enabledForTemplateDeployment: true`, and
- the deploying identity needs `Microsoft.KeyVault/vaults/deploy/action` on it (Owner/Contributor include it).

Replace the `<sub-id>` placeholders and vault name before using it.

---

## 4. Playground notes (where this folder differs from the Bicep kit)

The ARM files are the compact interview versions. They don't have the Bicep kit's feature flags, so on a restricted playground some steps fail as written:

| File | Behaviour | On KodeKloud | Workaround |
|------|-----------|--------------|------------|
| `rg.json` | Subscription-scope deployment | Denied (RG-scoped SPN) | Use the existing lab RG |
| `storage.parameters.json` | Fixed name `stdemo12345` | `StorageAccountAlreadyTaken` likely | Pass `-p stgName=...` |
| `network.json` | Two subnets (web, pe), no `snet-aks` | Fine | Use the Bicep module for AKS |
| `vm.json` | `Standard_B2s`, Premium disk | May hit size policy | Edit to `Standard_B1s` / `StandardSSD_LRS` |
| `keyvault.json` | Purge protection on, 90-day retention, always assigns a role | `RequestDisallowedByPolicy`, then `roleAssignments/write` denied | Use `../bicep/modules/07-security.bicep` with the playground flags |
| `keyvault.json` | No private endpoint | — | The Bicep module adds PE + private DNS |
| `rbac.json` | Always writes role assignments | Denied | Skip on the playground |

---

## 5. Bicep ↔ ARM

Compile any Bicep file and diff it with the hand-written JSON:

```bash
az bicep build -f ../bicep/modules/02-storage.bicep --outfile ../arm-built/02-storage.json
az bicep decompile -f network.json      # ARM -> Bicep, best effort, writes network.bicep
```

| Bicep | ARM JSON |
|-------|----------|
| `targetScope = 'subscription'` | `$schema: .../subscriptionDeploymentTemplate.json#` |
| `param x string = 'a'` | `"parameters": { "x": { "type": "string", "defaultValue": "a" } }` |
| `@secure()` | `"type": "securestring"` |
| `@allowed([...])`, `@minLength(3)` | `"allowedValues": [...]`, `"minLength": 3` |
| `nsg.id` | `[resourceId('Microsoft.Network/networkSecurityGroups', 'nsg-web')]` |
| implicit dependency from a reference | explicit `"dependsOn": [ ... ]` |
| `'st${uniqueString(resourceGroup().id)}'` | `[concat('st', uniqueString(resourceGroup().id))]` |
| `module` | `Microsoft.Resources/deployments` nested deployment |
| `.bicepparam` | `*.parameters.json` |

The main reason teams moved to Bicep: no `dependsOn` bookkeeping, no string-built expressions, a real compiler (Gate 1), and modules without nested-deployment boilerplate.
The deployment engine, the gates, and the commands are the same.
