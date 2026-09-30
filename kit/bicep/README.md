# Bicep Kit — Azure Landing Zone (Demo)

> Other approaches for the same resources: [Terraform](../terraform/README.md) · [ARM JSON](../arm/README.md) · [Azure CLI](../cli/README.md) · [Pipelines](../pipelines/README.md)

Modular Bicep that builds a small, secure Azure footprint: RG, storage, network, VM, AKS, RBAC, and Key Vault with a private endpoint.
Each module is **one concern, one file**, and every module follows the same layout:

```
// ========== TYPES ==========      user-defined types (shape validation)
// ========== PARAMS ==========     decorators = input contract (@allowed, @minLength, @minValue, @secure)
// ========== VARIABLES ==========  derived values / constants (role GUIDs)
// ========== RESOURCES ==========  the actual ARM resources
// ========== OUTPUTS ==========    what downstream modules consume
```

## Layout

| File | Scope | Creates | Key outputs |
|------|-------|---------|-------------|
| `main.bicep` + `main.bicepparam` | subscription | RG + calls all modules | `rgId`, `kvName` |
| `main-rg.bicep` + `main-rg.bicepparam` | resource group | Calls all modules into an **existing** RG, with feature flags | `kvName`, `stgName` |
| `deploy.sh` | shell | `./deploy.sh <validate\|what-if\|create> <main-rg\|main\|storage\|network\|vm\|aks\|security\|rbac\|mini>`, the same script the pipeline runs | — |
| `set-secrets.sh` | shell | Exports `SSH_PUBLIC_KEY` and `DB_PASSWORD` (reuses them if set, otherwise creates them) | — |
| `modules/01-rg.bicep` | subscription | Resource group with typed tags | `rgId`, `rgName` |
| `modules/02-storage.bicep` | resource group | StorageV2 (TLS1.2+, HTTPS-only, no public blob) + containers | `stgName`, `stgId`, `blobEndpoint` |
| `modules/03-network.bicep` | resource group | NSG + VNet with 3 subnets (web / pe / aks) | `vnetId`, `webSubnetId`, `peSubnetId`, `aksSubnetId` |
| `modules/04-vm.bicep` | resource group | NIC + Ubuntu 24.04 VM, SSH-only, system-assigned MI | `vmPrincipalId`, `vmPrivateIp` |
| `modules/05-aks.bicep` | resource group | AKS with Azure CNI, Entra RBAC, OIDC + workload identity | `aksId`, `oidcIssuer` |
| `modules/06-rbac.bicep` | resource group | Role assignments at RG and resource scope + custom role | assignment IDs, `customRoleId` |
| `modules/07-security.bicep` | resource group | UAMI, Key Vault (RBAC, private; purge protection and retention are params), PE + private DNS | `kvName`, `kvUri`, `uamiPrincipalId` |
| `modules/mini.bicep` | resource group | Storage + network + VM in a single file (standalone demo) | `stgName`, `vnetId`, `vmPrivateIp` |

Dependency flow (the same in `main.bicep` and `main-rg.bicep`):

```
rg ─┬─ storage ──────────────────────────┐
    ├─ network ─┬─ vm   (webSubnetId)    │
    │           ├─ aks  (aksSubnetId)    │
    │           └─ security (vnetId, peSubnetId) ─ rbac (uamiPrincipalId + stgName)
```

Bicep works out this order from the output-to-param references, so there is no `dependsOn` anywhere.
`main-rg.bicep` is the same graph minus the `rg` node, because the RG comes from `-g` on the command line.

---

## 1. Log in with the service principal (KodeKloud playground)

KodeKloud rotates the playground SPN secret roughly **every 75 minutes**. Never commit it. Put it in environment variables for the current shell only:

```bash
# Copy these values from the KodeKloud lab page (or run `showcreds` in the azure-client terminal)
export ARM_CLIENT_ID="<appId>"
export ARM_CLIENT_SECRET="<password>"
export ARM_TENANT_ID="<tenantId>"
export ARM_SUBSCRIPTION_ID="<subscriptionId>"
export RG="<kml_rg_...>"            # the pre-created lab resource group

echo ${#ARM_CLIENT_ID}              # must print 36; a truncated ID gives AADSTS700016

az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant   "$ARM_TENANT_ID"

az account set --subscription "$ARM_SUBSCRIPTION_ID"
az account show -o table              # confirm the right subscription
az group show -n "$RG" -o table       # confirm the SPN can see the lab RG
```

If you don't know the RG name, take it from what the SPN can see:

```bash
export RG=$(az group list --query "[0].name" -o tsv); echo "$RG"
```

When the secret rotates, commands fail with `AADSTS7000215: Invalid client secret` or `ExpiredAuthenticationToken`. To recover:

```bash
az logout
export ARM_CLIENT_SECRET="<new password>"
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
```

A **playground restart** issues a new SPN, a new secret and a new RG. Re-export all five variables.

> Why SPN and not `az login` interactively? Pipelines authenticate as a non-human identity. In real projects,
> prefer **workload identity federation (OIDC)** from GitHub Actions or Azure DevOps. It has no secret to rotate.
> The SPN secret here is the playground's constraint, not the target design.

---

## 2. Check what the existing SPN is allowed to do

Before deploying anything, find out what the SPN can and can't do. This takes about 30 seconds, and it tells you which modules will work and which feature flags to switch off.

### 2.1 Who am I (object ID)

```bash
# Via Microsoft Graph (may be blocked for playground SPNs)
export SPN_OID=$(az ad sp show --id "$ARM_CLIENT_ID" --query id -o tsv 2>/dev/null)

# Fallback without Graph: read the oid claim from the ARM access token
[ -n "$SPN_OID" ] || export SPN_OID=$(az account get-access-token --query accessToken -o tsv \
  | cut -d. -f2 | python3 -c "import sys,base64,json; s=sys.stdin.read().strip(); s+='='*(-len(s)%4); print(json.loads(base64.urlsafe_b64decode(s))['oid'])")

echo "SPN object id: $SPN_OID"
```

### 2.2 Role assignments (which roles, at which scope)

```bash
az role assignment list --assignee "$SPN_OID" --all \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table

# If --all is denied at subscription level, ask at RG level instead
az role assignment list --assignee "$SPN_OID" -g "$RG" \
  --query "[].{Role:roleDefinitionName, Scope:scope}" -o table
```

### 2.3 Effective permissions on the RG (the source of truth)

This returns the **combined** `actions` and `notActions` of every role the caller has on the RG, and it needs no Graph access:

```bash
az rest --method get \
  --url "https://management.azure.com/subscriptions/$ARM_SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Authorization/permissions?api-version=2022-04-01" \
  --query "value[].{actions:actions, notActions:notActions}" -o json
```

How to read it:

| You see | Meaning | Deploy impact |
|---------|---------|---------------|
| `actions: ["*"]` with `notActions` containing `Microsoft.Authorization/*/Write` | **Contributor** | Everything except role assignments → `deployRbac=false` |
| `actions: ["*"]` and no Authorization in `notActions` | **Owner** | All modules, including `06-rbac` and `kvRole` |
| Only specific provider actions | Custom / limited role | Deploy only modules whose providers are listed |

### 2.4 Can I deploy at subscription scope?

```bash
az deployment sub validate -l eastus -f modules/01-rg.bicep -p rgName=probe-rg -o none \
  && echo "subscription deployments: ALLOWED  -> main.bicep works" \
  || echo "subscription deployments: DENIED   -> use main-rg.bicep"
```

### 2.5 Policies that will deny resources

Policy *deny* effects fail at preflight (Gate 2). List them up front:

```bash
az policy assignment list --disable-scope-strict-match \
  --query "[].{Name:displayName, Scope:scope}" -o table

# Show the rule text of a specific definition (name comes from the error or the list above)
az policy definition show -n key_vault-tpm --query "{name:displayName, rule:policyRule}" -o json
```

Known playground limits (`global-limits` policy set):

| Resource | Policy requirement | Kit setting |
|----------|--------------------|-------------|
| Key Vault | Standard tier, soft delete **7 days**, **purge protection off** | `kvPurgeProtection=false`, `kvSoftDeleteDays=7` |
| VM | Small sizes only | `Standard_B1s` |
| Region | Limited | `eastus` |

### 2.6 Result → flags

| Check | Result on KodeKloud | Flag |
|-------|---------------------|------|
| Subscription deployment | Denied | Use `main-rg.bicep` (or ad-hoc) |
| `roleAssignments/write` | Denied | `deployRbac=false` / `deployRoleAssignment=false` |
| AKS quota | Usually unavailable | `deployAks=false` |
| KV policy | Purge protection + 7 days | `kvPurgeProtection=false`, `kvSoftDeleteDays=7` |

---

## 3. Validation — the core idea

A Bicep deployment passes through **four gates**. Each one catches a different class of error, and each one runs later and costs more than the one before it.

| # | Gate | Command | Needs Azure? | Catches |
|---|------|---------|--------------|---------|
| 1 | **Compile + lint** | `az bicep build -f x.bicep` | No | Syntax, type mismatches, wrong property names (BCP089), missing required params, linter rules (secure params with defaults, hard-coded env URLs, unused params) |
| 2 | **ARM preflight** | `az deployment group validate` | Yes | Param values against `@allowed`/`@minLength`/`@minValue`, name format/length, SKU availability in region, quota, Azure Policy *deny*, RBAC on the deployment scope |
| 3 | **What-if** | `az deployment group what-if` | Yes | Nothing "fails" — it shows the **diff** (Create / Modify / Delete / NoChange) against live state, so you catch unintended drift or destructive changes |
| 4 | **Deploy** | `az deployment group create` | Yes | Resource-provider runtime errors: globally unique name taken, CIDR overlap, dependent resource not ready, soft-deleted Key Vault name collision |

### Where each decorator is enforced

When a value arrives decides which gate enforces the rule:

- **Literal in a `.bicepparam` file or a module call:** the Bicep compiler rejects it at **Gate 1**.
- **Passed with `-p` on the CLI or by a pipeline:** Bicep never sees it. ARM rejects it at **Gate 2**, using the constraints that were compiled into the JSON.

| Decorator / feature | Example in this kit | Gate 1 error (bicepparam literal) | Gate 2 (CLI `-p`) |
|---------------------|---------------------|-----------------------------------|-------------------|
| `@allowed([...])` | `skuName`, `vmSize`, `location` | BCP033 | `allowedValues` |
| Literal union type | `env: 'dev' \| 'test' \| 'prod'` in 01-rg | BCP036 | `allowedValues` |
| `@minLength` / `@maxLength` | `stgName` 3–24, `principalId` 36 | BCP332 | `minLength`/`maxLength` |
| `@minValue` / `@maxValue` | AKS `nodeCount` 1–5, KV retention 7–90 | BCP327 | `minValue`/`maxValue` |
| `@minLength` on arrays | `subnets` ≥ 3 (outputs index [0..2]) | BCP333 | `minLength` |
| User-defined `type` | `subnetType`, `imageType`, `aksNetworkType` | BCP035/BCP036 (missing or wrong property) | schema check |
| `@secure()` | `dbPassword` | — | Not a check. It keeps the value out of deployment history and logs |
| `@description` | most params | — | Docs only; shows up in the portal and in IntelliSense |

You can see this for yourself: compile `modules/mini.bicep` and open `modules/mini.json`. The decorators come out as
`allowedValues`, `minLength`, and `maxLength` on each parameter. Those constraints are what ARM checks at preflight.

### Run all gates against the lab RG

```bash
cd ValueMomentum/kit/bicep

# Gate 1 — every file, no Azure call
for f in modules/*.bicep main.bicep main-rg.bicep; do az bicep build -f "$f" --stdout >/dev/null && echo "OK  $f"; done
az bicep lint -f main-rg.bicep

# Gate 2 — preflight (example: network)
az deployment group validate -g "$RG" -f modules/03-network.bicep -o table

# Gate 3 — diff against live state
az deployment group what-if -g "$RG" -f modules/03-network.bicep

# Gate 4 — deploy
az deployment group create -g "$RG" -f modules/03-network.bicep -n network -o table
```

To **read** the ARM JSON that Bicep produces, write it to a file instead of discarding it:

```bash
mkdir -p ../arm-built
for f in modules/*.bicep main.bicep main-rg.bicep; do
  az bicep build -f "$f" --outfile "../arm-built/$(basename "${f%.bicep}").json" && echo "built $f"
done
```

### Demo: make validation fail on purpose

```bash
# @allowed violation -> Gate 2 rejects before anything is created
az deployment group validate -g "$RG" -f modules/02-storage.bicep -p skuName=Premium_XYZ

# @maxLength violation (25 chars)
az deployment group validate -g "$RG" -f modules/02-storage.bicep -p stgName=abcdefghijklmnopqrstuvwxy

# @maxValue violation
az deployment group validate -g "$RG" -f modules/05-aks.bicep -p subnetId=x nodeCount=9

# Array @minLength violation (only 1 subnet)
az deployment group validate -g "$RG" -f modules/03-network.bicep \
  -p subnets='[{"name":"snet-web","prefix":"10.0.1.0/24"}]'
```

---

## 4. Secrets for the session

`04-vm` needs an SSH public key, and `07-security` optionally stores a DB password in Key Vault. `set-secrets.sh` **reuses** values that are already set and **creates** them when they aren't:

```bash
#!/usr/bin/env bash
# Usage: source ./set-secrets.sh   ('source', so the exports stay in your shell)
if [ -z "${SSH_PUBLIC_KEY:-}" ]; then
  [ -f ~/.ssh/id_rsa.pub ] || ssh-keygen -t rsa -b 4096 -N "" -f ~/.ssh/id_rsa -q
  export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
fi
SECRET_FILE=~/.azdemo-db-password
if [ -z "${DB_PASSWORD:-}" ]; then
  [ -f "$SECRET_FILE" ] || (umask 077; openssl rand -base64 18 > "$SECRET_FILE")
  export DB_PASSWORD="$(cat "$SECRET_FILE")"
fi
echo "SSH_PUBLIC_KEY set: ${SSH_PUBLIC_KEY:0:20}...  DB_PASSWORD set: yes"
```

```bash
chmod +x set-secrets.sh
source ./set-secrets.sh
```

The password is saved (mode 600) so every redeploy writes the **same** secret instead of rotating it.

---

## 5. Deploy

Pick the option that matches what section 2 told you.

| Option | Scope | Needs | Best for |
|--------|-------|-------|----------|
| **A — Ad-hoc, module by module** | RG | RG Contributor | Learning, debugging one module at a time |
| **B — `main-rg.bicep` + `main-rg.bicepparam`** | RG | RG Contributor | One-shot deploy into an existing RG (KodeKloud) |
| **C — `main.bicep` + `main.bicepparam`** | subscription | Subscription deployment rights | Creating the RG too |
| **D — `mini.bicep`** | RG | RG Contributor | Single-file demo |

### Option A — Ad-hoc, module by module (recommended first run on KodeKloud)

Each step is **validate → what-if → create → verify**. Don't move on until the step before it succeeds.

```bash
cd ValueMomentum/kit/bicep
source ./set-secrets.sh
```

**Step 1 — Storage**

```bash
az deployment group validate -g "$RG" -f modules/02-storage.bicep -o none && echo "valid"
az deployment group what-if  -g "$RG" -f modules/02-storage.bicep
az deployment group create   -g "$RG" -f modules/02-storage.bicep -n storage -o table

STG=$(az deployment group show -g "$RG" -n storage --query properties.outputs.stgName.value -o tsv)
az storage account show -g "$RG" -n "$STG" --query "{name:name, tls:minimumTlsVersion, httpsOnly:enableHttpsTrafficOnly}" -o table
```

**Step 2 — Network**

```bash
az deployment group validate -g "$RG" -f modules/03-network.bicep -o none && echo "valid"
az deployment group what-if  -g "$RG" -f modules/03-network.bicep
az deployment group create   -g "$RG" -f modules/03-network.bicep -n network -o table

WEB=$(az deployment group show  -g "$RG" -n network --query properties.outputs.webSubnetId.value -o tsv)
PE=$(az deployment group show   -g "$RG" -n network --query properties.outputs.peSubnetId.value  -o tsv)
AKS=$(az deployment group show  -g "$RG" -n network --query properties.outputs.aksSubnetId.value -o tsv)
VNET=$(az deployment group show -g "$RG" -n network --query properties.outputs.vnetId.value      -o tsv)

az network vnet subnet list -g "$RG" --vnet-name vnet-demo --query "[].{Name:name, Prefix:addressPrefix}" -o table
```

**Step 3 — VM** (needs `WEB` from step 2)

```bash
az deployment group what-if -g "$RG" -f modules/04-vm.bicep \
  -p subnetId="$WEB" sshPublicKey="$SSH_PUBLIC_KEY"
az deployment group create  -g "$RG" -f modules/04-vm.bicep -n vm \
  -p subnetId="$WEB" sshPublicKey="$SSH_PUBLIC_KEY" -o table
# If policy rejects the size and your 04-vm exposes vmSize, add: -p vmSize=Standard_B1s

az deployment group show -g "$RG" -n vm --query properties.outputs -o json
```

**Step 4 — Security: identity, Key Vault, private endpoint** (needs `VNET` and `PE` from step 2)

Playground values: no role assignment, no purge protection, 7-day soft delete.

```bash
SEC_PARAMS=(vnetId="$VNET" peSubnetId="$PE" dbPassword="$DB_PASSWORD"
            deployRoleAssignment=false enablePurgeProtection=false softDeleteRetentionInDays=7)

az deployment group validate -g "$RG" -f modules/07-security.bicep -p "${SEC_PARAMS[@]}" -o none && echo "valid"
az deployment group what-if  -g "$RG" -f modules/07-security.bicep -p "${SEC_PARAMS[@]}"
az deployment group create   -g "$RG" -f modules/07-security.bicep -n security -p "${SEC_PARAMS[@]}" -o table

KV=$(az deployment group show -g "$RG" -n security --query properties.outputs.kvName.value -o tsv)
az keyvault show -n "$KV" --query "{softDelete:properties.softDeleteRetentionInDays, purge:properties.enablePurgeProtection, public:properties.publicNetworkAccess}" -o table
az network private-endpoint list -g "$RG" --query "[].customDnsConfigs[].{fqdn:fqdn, ip:ipAddresses[0]}" -o table
```

**Step 5 — RBAC** (only if section 2.3 showed Owner or User Access Administrator)

```bash
UAMI_PID=$(az deployment group show -g "$RG" -n security --query properties.outputs.uamiPrincipalId.value -o tsv)
az deployment group create -g "$RG" -f modules/06-rbac.bicep -n rbac \
  -p principalId="$UAMI_PID" stgName="$STG" -o table
```

**Step 6 — AKS** (only if quota and policy allow it)

```bash
az deployment group create -g "$RG" -f modules/05-aks.bicep -n aks -p subnetId="$AKS" -o table
```

### Option B — One shot into the existing RG: `main-rg.bicep` + `main-rg.bicepparam`

This uses the same modules and dependency graph as `main.bicep`, but at **RG scope**, so it works with an RG-scoped SPN.
Feature flags switch off whatever section 2 found you're not allowed to do.

`main-rg.bicep`

```bicep
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
```

`main-rg.bicepparam`

```bicep
using 'main-rg.bicep'

param deployVm = true
param deployAks = false
param deployRbac = false
param kvPurgeProtection = false // playground policy: no purge protection
param kvSoftDeleteDays = 7      // playground policy: 7-day soft delete
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY')
param dbPassword = readEnvironmentVariable('DB_PASSWORD')
```

There's no `rgName` here, because the RG comes from `-g`. `readEnvironmentVariable()` has **no fallback** on purpose:
if `set-secrets.sh` wasn't sourced, the build fails with `BCP427` instead of sending an empty SSH key to Azure.

Run it:

```bash
source ./set-secrets.sh

az bicep build -f main-rg.bicep --stdout >/dev/null && echo "template OK"
az bicep build-params -f main-rg.bicepparam --stdout >/dev/null && echo "params OK"

az deployment group validate -g "$RG" -p main-rg.bicepparam -o none && echo "valid"
az deployment group what-if  -g "$RG" -p main-rg.bicepparam
az deployment group create   -g "$RG" -p main-rg.bicepparam -n main-rg -o table

az deployment group show -g "$RG" -n main-rg --query properties.outputs -o json
```

With a `.bicepparam` file, `-f` is not needed, because the `using` line points at the template.
Override a single flag without editing the file:

```bash
az deployment group create -g "$RG" -p main-rg.bicepparam -p deployVm=false -n main-rg
```

Each module shows up as its own nested deployment (`storage`, `network`, `vm`, `security`), so you can inspect one:

```bash
az deployment group list -g "$RG" --query "[].{Name:name, State:properties.provisioningState}" -o table
```

### Option C — One shot with RG creation: `main.bicep` (needs subscription-scope deployment rights)

```bash
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
export DB_PASSWORD="<optional>"
# set rgName in main.bicepparam to the target RG first
az deployment sub what-if -l eastus -f main.bicep -p main.bicepparam
az deployment sub create  -l eastus -f main.bicep -p main.bicepparam
```

The rule is **file scope = command scope**: `targetScope = 'subscription'` → `az deployment sub`. Running it with
`az deployment group` fails with *"The target scope "subscription" does not match the deployment scope "resourceGroup"."*

### Option D — Single file

```bash
az deployment group create -g "$RG" -f modules/mini.bicep -p sshPublicKey="$SSH_PUBLIC_KEY"
```

### Same thing, one script (and in the pipeline)

`deploy.sh` wraps Options A–D. Single modules pick up their inputs from earlier deployments, the same way Option A does by hand:

```bash
source ./modules/set-secrets.sh
./deploy.sh what-if main-rg          # Option B
./deploy.sh create  network          # Option A, step by step
./deploy.sh create  vm               # reads webSubnetId from the 'network' deployment
EXTRA_PARAMS="deployVm=false" ./deploy.sh create main-rg
```

`kit/pipelines/azure-pipelines.yml` runs exactly these commands (tool `bicep`, target of your choice). See `kit/README.md` section 7.

---

## 6. Verify and troubleshoot

```bash
# What exists (hide the lab's own resources)
az resource list -g "$RG" --query "[?!starts_with(name,'nautilus')].{Name:name, Type:type}" -o table

# Every deployment and its state
az deployment group list -g "$RG" --query "[].{Name:name, State:properties.provisioningState, Time:properties.timestamp}" -o table

# Why a deployment failed (use the module name for nested failures: storage, network, vm, security)
az deployment operation group list -g "$RG" -n main-rg \
  --query "[?properties.provisioningState=='Failed'].{resource:properties.targetResource.resourceName, error:properties.statusMessage.error.message}" -o json
```

Reading **what-if** output:

| Symbol | Meaning | Note |
|--------|---------|------|
| `+` Create | New resource | |
| `~` Modify | Properties differ | `-` lines on Azure-populated defaults (e.g. `allowPort25Out`, `privateIPAddress`) are what-if noise; Incremental mode keeps them |
| `=` NoChange | Matches the template | Idempotency |
| `x` NoEffect | Differs but can't be changed in place | e.g. OS disk type on an existing VM |
| `*` Ignore | In the RG but not in the template | The `nautilus-*` lab resources. Incremental leaves them alone; **Complete mode would delete them** |
| "MAY OR MAY NOT" | Conditional resource | e.g. the secret behind `if (!empty(dbPassword))` |

Clean up your resources only (the lab owns the RG):

```bash
az resource list -g "$RG" --query "[?!starts_with(name,'nautilus')].id" -o tsv | xargs -r -n1 az resource delete --ids
```

---

## 7. KodeKloud playground gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AADSTS700016: Application ... was not found` | `ARM_CLIENT_ID` copied incompletely | `echo ${#ARM_CLIENT_ID}` must be 36 |
| `AuthorizationFailed ... Microsoft.Resources/deployments/write` at subscription | SPN is scoped to the lab RG only | Use Option A/B/D (`az deployment group`) |
| `The target scope "subscription" does not match the deployment scope "resourceGroup"` | `main.bicep` run with `az deployment group` | Use `main-rg.bicep`, or `az deployment sub` with rights |
| `AuthorizationFailed ... roleAssignments/write` | Playground SPN is usually not Owner or User Access Administrator | `deployRbac=false` (skips `06-rbac` **and** `kvRole` in 07) |
| `RequestDisallowedByPolicy` on Key Vault | `global-limits` policy: 7-day soft delete, no purge protection | `kvPurgeProtection=false`, `kvSoftDeleteDays=7` (07 sends `null`, not `false`) |
| `SkuNotAvailable` / `RequestDisallowedByPolicy` on VM | Playground policy limits VM/AKS sizes and regions | Stick to `Standard_B1s` / `eastus`. Policy *deny* shows up at Gate 2 |
| `StorageAccountAlreadyTaken` | Global name collision | Default `uniqueString(resourceGroup().id)` avoids it |
| `VaultAlreadyExists` / soft-deleted vault | A deleted vault keeps its name for the retention period | Pass a new `kvName` |
| `BCP261: A using declaration must be present` | Empty `.bicepparam`, stray ```` ``` ```` line, or CRLF/BOM from Windows Notepad | Recreate with `cat > file <<'EOF'` or run `dos2unix` |
| `BCP427: Environment variable ... does not exist` | Secrets not exported | `source ./set-secrets.sh` |
| `BCP028: Identifier ... declared multiple times` | Param pasted twice while merging | `grep -n "^param" file.bicep` |
| `[Errno 101] Network is unreachable` (WSL) | az CLI tries IPv6 with no route | `echo 'precedence ::ffff:0:0/96 100' \| sudo tee -a /etc/gai.conf` |
| Commands suddenly 401 | SPN secret rotated (~75 min) | Re-run section 1 |

---

## 8. Design decisions (talking points)

- **Idempotent, declarative.** Re-running a deployment converges to the same state. `guid(scope, principal, role)` makes role-assignment names deterministic, so a re-run is a no-op and doesn't hit a conflict.
- **Implicit dependencies.** Referencing `nsg.id` or `network.outputs.x` builds the DAG. `dependsOn` only appears when there's no data reference, and this kit doesn't need it anywhere.
- **Two entry points, one set of modules.** `main.bicep` (subscription scope) creates the RG when you own the subscription. `main-rg.bicep` (RG scope) reuses the same modules when you only have RG access, which is common in enterprise landing zones.
- **Feature flags for environment limits.** `deployRbac`, `deployAks` and `deployVm` let one template serve environments with different permissions and quotas, instead of forking the code.
- **Secure by default, compliant by parameter.** Purge protection and 90-day retention are the defaults. Where policy demands otherwise, each environment's `.bicepparam` sets `kvPurgeProtection=false` and `kvSoftDeleteDays=7`. `? true : null` handles properties that ARM won't accept as `false`.
- **Least privilege.** Roles are assigned at resource scope (blob contributor on one storage account) instead of the RG, and there's a custom role limited to three VM actions. Role-assignment writes sit behind a flag, so a Contributor-only pipeline identity never needs Owner.
- **Secrets never in templates.** `@secure()` params, values come from environment variables through `readEnvironmentVariable()` in `.bicepparam`, and the Key Vault secret is written through the ARM control plane, so it works while the vault's public access is disabled.
- **Private by default.** Key Vault has public access disabled, a PE in `snet-pe`, and the `privatelink.vaultcore.azure.net` zone linked to the VNet. The mnemonic for the four hardening settings is **R-S-P-N** (RBAC, Soft delete, Purge protection, Network deny).
- **Keyless identity.** The VM uses a system-assigned MI, the app uses a UAMI, and AKS has OIDC + workload identity, so no app needs a client secret.
- **Shift-left validation.** Types and decorators move errors from Gate 4 (slow, partial deploys) to Gates 1–2 (seconds, nothing created). Checking SPN permissions and policies first (section 2) moves the remaining surprises out of the deploy step altogether.


export RG=$(az group list --query "[0].name" -o tsv); echo "$RG"
./cleanup.sh               # dry run: check the list
./cleanup.sh --yes         # delete