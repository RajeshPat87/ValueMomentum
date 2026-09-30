# ARM JSON Kit — Azure Landing Zone (Demo)

Hand-written ARM templates for the same resources as the [Bicep kit](../bicep/README.md). ARM JSON is what Bicep compiles to and what Azure Resource Manager actually runs,
so this folder is the "under the hood" view: same deploy commands, same validation gates, same feature flags, more syntax.

## Layout

| File | Scope | Creates | Outputs |
|------|-------|---------|---------|
| `rg.json` | subscription | Resource group | `rgId` |
| `storage.json` + `storage.parameters.json` | resource group | StorageV2 + `data` container (`skuName` param) | `stgId`, `stgName` |
| `network.json` | resource group | `nsg-web` + `vnet-demo` with `snet-web`, `snet-pe`, `snet-aks` | `vnetId`, `webSubnetId`, `peSubnetId`, `aksSubnetId` |
| `vm.json` | resource group | NIC + `vm01` (Ubuntu, SSH only, system-assigned MI; `vmSize`, `osDiskType` params) | `principalId` |
| `vm.parameters.kvref.json` | — | Parameter file that pulls `sshPublicKey` from Key Vault at deploy time | — |
| `keyvault.json` | resource group | UAMI + Key Vault (RBAC, private) + optional secret + optional role + private endpoint & DNS | `kvName`, `kvUri`, `uamiPrincipalId` |
| `keyvault.playground.parameters.json` | — | Playground values: no purge protection, 7-day soft delete, no role assignment | — |
| `rbac.json` | resource group | Reader on the RG + Blob Data Contributor on one storage account | — |
| `deploy.sh` | shell | `./deploy.sh <validate\|what-if\|create> <rg\|storage\|network\|vm\|keyvault\|rbac>` | — |
| [`../arm-built/`](../arm-built) | — | ARM JSON **generated** from the Bicep modules (`az bicep build`), for comparison | — |

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
there is no compiler, so a JSON or expression typo surfaces at Gate 2 (`validate`) instead of on your machine.

---

## 3. Deploy

### With `deploy.sh` (dependencies wired for you)

Each target reads what it needs from earlier deployments, the same way the Bicep `deploy.sh` does:

```bash
./deploy.sh create storage
./deploy.sh create network
./deploy.sh create vm                                                     # reads webSubnetId from 'network'
EXTRA_PARAMS=@keyvault.playground.parameters.json ./deploy.sh create keyvault   # reads vnetId + peSubnetId
./deploy.sh create rbac                                                   # needs Owner / UAA; reads uamiPrincipalId + stgName
```

Use `validate` or `what-if` in place of `create` to stop at Gate 2 or 3. `rg` is subscription scope (`RG_NAME=... ./deploy.sh create rg`); skip it on KodeKloud.
Deployment names equal the target, so `../bicep/modules/cleanup.sh` finds these resources too.

### By hand (what `deploy.sh` runs)

```bash
az deployment group create -g "$RG" -f storage.json -p @storage.parameters.json -n storage -o table
az deployment group create -g "$RG" -f network.json -n network -o table
out() { az deployment group show -g "$RG" -n "$1" --query "properties.outputs.$2.value" -o tsv; }

az deployment group create -g "$RG" -f vm.json -n vm \
  -p subnetId="$(out network webSubnetId)" sshPublicKey="$SSH_PUBLIC_KEY" -o table

az deployment group create -g "$RG" -f keyvault.json -n keyvault \
  -p vnetId="$(out network vnetId)" peSubnetId="$(out network peSubnetId)" dbPassword="$DB_PASSWORD" \
  -p @keyvault.playground.parameters.json -o table

az deployment group create -g "$RG" -f rbac.json -n rbac \
  -p principalId="$(out keyvault uamiPrincipalId)" stgName="$(out storage stgName)" -o table
```

`-p` can repeat and mixes `name=value` with `@file.json`; later values win.

### Feature flags (same as the Bicep kit)

| Parameter | File | Default | Playground | Bicep equivalent |
|-----------|------|---------|------------|------------------|
| `enablePurgeProtection` | `keyvault.json` | `true` | `false` | `enablePurgeProtection` / `kvPurgeProtection` |
| `softDeleteRetentionInDays` | `keyvault.json` | `90` | `7` | same name / `kvSoftDeleteDays` |
| `deployRoleAssignment` | `keyvault.json` | `true` | `false` | same name / `deployRbac` |
| `dbPassword` | `keyvault.json` | `''` (no secret) | from `set-secrets.sh` | same |
| `vnetId` + `peSubnetId` | `keyvault.json` | `''` (no PE) | from `network` outputs | required in Bicep |
| `vmSize`, `osDiskType` | `vm.json` | `Standard_B1s`, `StandardSSD_LRS` | same | same |
| `skuName` | `storage.json` | `Standard_LRS` | same | same |

Two ARM-specific patterns in `keyvault.json`:

- `"condition": "[parameters('deployRoleAssignment')]"` is how ARM writes Bicep's `resource x = if (flag)`.
- `"enablePurgeProtection": "[if(parameters('enablePurgeProtection'), true(), null())]"`: ARM rejects `false` for this property, so the template omits it instead.

### Parameter files and Key Vault references

`vm.parameters.kvref.json` shows the pattern for secrets: instead of a `value`, the parameter holds a `reference` to a Key Vault secret, and ARM reads it during deployment.
The secret never appears on the command line or in deployment history. For that to work:

- the referenced vault must have `enabledForTemplateDeployment: true`, and
- the deploying identity needs `Microsoft.KeyVault/vaults/deploy/action` on it (Owner/Contributor include it).

Replace the `<sub-id>` placeholders and vault name before using it.

---

## 4. Playground notes

| Step | On KodeKloud |
|------|--------------|
| `rg` | Denied (RG-scoped SPN). Use the lab RG |
| `keyvault` | Pass `@keyvault.playground.parameters.json`, otherwise `RequestDisallowedByPolicy` and `roleAssignments/write` denied |
| `rbac` | Denied without Owner / User Access Administrator. Skip it |
| AKS | No ARM file; use `../bicep/modules/05-aks.bicep` (the `snet-aks` subnet is created here) |

Troubleshooting is the same as the Bicep kit: [Bicep README section 6](../bicep/README.md#6-verify-and-troubleshoot).

---

## 5. Bicep ↔ ARM

Compile any Bicep file and diff it with the hand-written JSON:

```bash
az bicep build -f ../bicep/modules/02-storage.bicep --outfile ../arm-built/02-storage.json
az bicep decompile -f network.json      # ARM -> Bicep, best effort, writes network.bicep
```

`decompile` is best effort: a `dependsOn` written through a variable (as in `network.json`) comes back as a plain string and needs a hand fix.

| Bicep | ARM JSON |
|-------|----------|
| `targetScope = 'subscription'` | `$schema: .../subscriptionDeploymentTemplate.json#` |
| `param x string = 'a'` | `"parameters": { "x": { "type": "string", "defaultValue": "a" } }` |
| `@secure()` | `"type": "securestring"` |
| `@allowed([...])`, `@minLength(3)` | `"allowedValues": [...]`, `"minLength": 3` |
| `resource x ... = if (flag)` | `"condition": "[parameters('flag')]"` |
| `nsg.id` | `[resourceId('Microsoft.Network/networkSecurityGroups', 'nsg-web')]` |
| implicit dependency from a reference | explicit `"dependsOn": [ ... ]` |
| `'st${uniqueString(resourceGroup().id)}'` | `[concat('st', uniqueString(resourceGroup().id))]` |
| `module` | `Microsoft.Resources/deployments` nested deployment |
| `.bicepparam` | `*.parameters.json` |

The main reason teams moved to Bicep: no `dependsOn` bookkeeping, no string-built expressions, a real compiler (Gate 1), and modules without nested-deployment boilerplate.
The deployment engine, the gates, and the commands are the same.
