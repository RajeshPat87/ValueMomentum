# Bicep Kit — Azure Landing Zone (Demo)

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
| `modules/01-rg.bicep` | subscription | Resource group with typed tags | `rgId`, `rgName` |
| `modules/02-storage.bicep` | resource group | StorageV2 (TLS1.2+, HTTPS-only, no public blob) + containers | `stgName`, `stgId`, `blobEndpoint` |
| `modules/03-network.bicep` | resource group | NSG + VNet with 3 subnets (web / pe / aks) | `vnetId`, `webSubnetId`, `peSubnetId`, `aksSubnetId` |
| `modules/04-vm.bicep` | resource group | NIC + Ubuntu 24.04 VM, SSH-only, system-assigned MI | `vmPrincipalId`, `vmPrivateIp` |
| `modules/05-aks.bicep` | resource group | AKS with Azure CNI, Entra RBAC, OIDC + workload identity | `aksId`, `oidcIssuer` |
| `modules/06-rbac.bicep` | resource group | Role assignments at RG and resource scope + custom role | assignment IDs, `customRoleId` |
| `modules/07-security.bicep` | resource group | UAMI, Key Vault (RBAC, purge-protected, private), PE + private DNS | `kvName`, `kvUri`, `uamiPrincipalId` |
| `modules/mini.bicep` | resource group | Storage + network + VM in a single file (standalone demo) | `stgName`, `vnetId`, `vmPrivateIp` |

Dependency flow in `main.bicep`:

```
rg ─┬─ storage ──────────────────────────┐
    ├─ network ─┬─ vm   (webSubnetId)    │
    │           ├─ aks  (aksSubnetId)    │
    │           └─ security (vnetId, peSubnetId) ─ rbac (uamiPrincipalId + stgName)
```

Bicep works out this order from the output-to-param references, so there is no `dependsOn` anywhere.

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

az login --service-principal \
  --username "$ARM_CLIENT_ID" \
  --password "$ARM_CLIENT_SECRET" \
  --tenant   "$ARM_TENANT_ID"

az account set --subscription "$ARM_SUBSCRIPTION_ID"
az account show -o table              # confirm the right subscription
az group show -n "$RG" -o table       # confirm the SPN can see the lab RG
```

When the secret rotates, commands fail with `AADSTS7000215: Invalid client secret` or `ExpiredAuthenticationToken`. To recover:

```bash
az logout
export ARM_CLIENT_SECRET="<new password>"
az login --service-principal -u "$ARM_CLIENT_ID" -p "$ARM_CLIENT_SECRET" --tenant "$ARM_TENANT_ID"
```

> Why SPN and not `az login` interactively? Pipelines authenticate as a non-human identity. In real projects,
> prefer **workload identity federation (OIDC)** from GitHub Actions or Azure DevOps. It has no secret to rotate.
> The SPN secret here is the playground's constraint, not the target design.

---

## 2. Validation — the core idea

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
for f in modules/*.bicep main.bicep; do az bicep build -f "$f" --stdout >/dev/null && echo "OK  $f"; done
az bicep lint -f main.bicep

# Gate 2 — preflight (example: network)
az deployment group validate -g "$RG" -f modules/03-network.bicep -o table

# Gate 3 — diff against live state
az deployment group what-if -g "$RG" -f modules/03-network.bicep

# Gate 4 — deploy
az deployment group create -g "$RG" -f modules/03-network.bicep -n network -o table
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

## 3. Deploy

### Option A — module by module (works with RG-scoped SPN; recommended on KodeKloud)

```bash
az deployment group create -g "$RG" -f modules/02-storage.bicep -n storage
az deployment group create -g "$RG" -f modules/03-network.bicep -n network

WEB=$(az deployment group show -g "$RG" -n network --query properties.outputs.webSubnetId.value -o tsv)
PE=$(az deployment group show  -g "$RG" -n network --query properties.outputs.peSubnetId.value  -o tsv)
VNET=$(az deployment group show -g "$RG" -n network --query properties.outputs.vnetId.value     -o tsv)

az deployment group create -g "$RG" -f modules/04-vm.bicep -n vm \
  -p subnetId="$WEB" sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"

az deployment group create -g "$RG" -f modules/07-security.bicep -n security \
  -p vnetId="$VNET" peSubnetId="$PE"
```

### Option B — one shot via `main.bicep` (needs subscription-scope deployment rights)

```bash
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
export DB_PASSWORD="<optional>"
# set rgName in main.bicepparam to the lab RG first
az deployment sub what-if -l eastus -f main.bicep -p main.bicepparam
az deployment sub create  -l eastus -f main.bicep -p main.bicepparam
```

### Option C — single file

```bash
az deployment group create -g "$RG" -f modules/mini.bicep -p sshPublicKey="$(cat ~/.ssh/id_rsa.pub)"
```

---

## 4. KodeKloud playground gotchas

| Symptom | Cause | Fix |
|---------|-------|-----|
| `AuthorizationFailed ... Microsoft.Resources/deployments/write` at subscription | SPN is scoped to the lab RG only | Use Option A/C (`az deployment group`) |
| `AuthorizationFailed ... roleAssignments/write` | Playground SPN is usually not Owner or User Access Administrator | Skip 06-rbac and the `kvRole` in 07, or explain them as design |
| `SkuNotAvailable` / `RequestDisallowedByPolicy` | Playground policy limits VM/AKS sizes and regions | Stick to `Standard_B1s` / `eastus`. Policy *deny* shows up at Gate 2 |
| `StorageAccountAlreadyTaken` | Global name collision | Default `uniqueString(resourceGroup().id)` avoids it |
| `VaultAlreadyExists` / soft-deleted vault | Purge protection keeps the name reserved for up to 90 days | Pass a new `kvName` |
| Commands suddenly 401 | SPN secret rotated (~75 min) | Re-run section 1 |

---

## 5. Design decisions (talking points)

- **Idempotent, declarative.** Re-running a deployment converges to the same state. `guid(scope, principal, role)` makes role-assignment names deterministic, so a re-run is a no-op and doesn't hit a conflict.
- **Implicit dependencies.** Referencing `nsg.id` or `network.outputs.x` builds the DAG. `dependsOn` only appears when there's no data reference, and this kit doesn't need it anywhere.
- **Least privilege.** Roles are assigned at resource scope (blob contributor on one storage account) instead of the RG, and there's a custom role limited to three VM actions.
- **Secrets never in templates.** `@secure()` params, values come from environment variables through `readEnvironmentVariable()` in `.bicepparam`, and the Key Vault secret is written through the ARM control plane, so it works while the vault's public access is disabled.
- **Private by default.** Key Vault has public access disabled, a PE in `snet-pe`, and the `privatelink.vaultcore.azure.net` zone linked to the VNet. The mnemonic for the four hardening settings is **R-S-P-N** (RBAC, Soft delete, Purge protection, Network deny).
- **Keyless identity.** The VM uses a system-assigned MI, the app uses a UAMI, and AKS has OIDC + workload identity, so no app needs a client secret.
- **Shift-left validation.** Types and decorators move errors from Gate 4 (slow, partial deploys) to Gates 1–2 (seconds, nothing created).
