# Azure CLI Kit — Azure Landing Zone (Demo)

The same resources as the other kits, two ways with the Azure CLI:

| Script | Style | What it shows |
|--------|-------|---------------|
| `01-direct-create.sh` | **Imperative**: one `az <noun> create` per resource | Exact CLI syntax for RG, storage, VNet/NSG, VM, AKS, identity, Key Vault + PE, RBAC, custom role, policy. Same feature flags as Bicep |
| `02-deploy-templates.sh` | **Declarative**: `az deployment ...` with the Bicep and ARM files | Scope rule, what-if, `bicep build`/`decompile`, deployment stacks, troubleshooting |

---

## 1. Log in and set secrets

Same service principal and secrets as the Bicep kit: [Bicep README section 1](../bicep/README.md#1-log-in-with-the-service-principal-kodekloud-playground).

```bash
cd ValueMomentum/kit/cli
source ../bicep/modules/az-login.sh      # exports RG and ARM_SUBSCRIPTION_ID
source ../bicep/modules/set-secrets.sh   # exports SSH_PUBLIC_KEY and DB_PASSWORD
```

---

## 2. `01-direct-create.sh`

### Run it

```bash
# KodeKloud playground (RG-scoped SPN, Key Vault policy)
DEPLOY_RBAC=false KV_PURGE_PROTECTION=false KV_SOFT_DELETE_DAYS=7 ./01-direct-create.sh

# Your own subscription: secure defaults, creates rg-demo if $RG is unset
./01-direct-create.sh
```

### Inputs

Environment variables with the same meaning as the Bicep flags:

| Variable | Default | Playground | Bicep flag |
|----------|---------|------------|------------|
| `RG` | `rg-demo` | lab RG (from `az-login.sh`) | `-g` / `rgName` |
| `LOC` | `eastus` | — (an existing RG keeps its region) | `location` |
| `VM_SIZE` | `Standard_B1s` | same | `vmSize` |
| `DEPLOY_VM` | `true` | `true` | `deployVm` |
| `DEPLOY_AKS` | `false` | `false` | `deployAks` |
| `DEPLOY_RBAC` | `true` | `false` | `deployRbac` (role assignments, custom role, policy) |
| `KV_PURGE_PROTECTION` | `true` | `false` | `kvPurgeProtection` |
| `KV_SOFT_DELETE_DAYS` | `90` | `7` | `kvSoftDeleteDays` |
| `SSH_PUBLIC_KEY` | required | `set-secrets.sh` | `sshPublicKey` |
| `DB_PASSWORD` | empty = no secret | `set-secrets.sh` | `dbPassword` |

The RG is only created when it doesn't exist. Storage and Key Vault names get a suffix hashed from subscription + RG,
so a re-run reuses the same names instead of creating new resources (most `az ... create` commands are idempotent PUTs).

### Section by section

| Section | Resources | Order matters because |
|---------|-----------|-----------------------|
| Resource group | reuse `$RG` or create it | Everything else lives in it |
| Storage | `stdemo<hash>` + `data` container | Container is a child of the account |
| Networking | `nsg-web` (rule `Allow-443-In`), `vnet-demo`, `snet-web` / `snet-pe` / `snet-aks`, NSG on every subnet | VM, AKS and PE need subnet IDs |
| VM | `vm01`, no public IP, StandardSSD disk, system-assigned MI | Needs `WEB_SUBNET_ID` |
| AKS | `aks-demo`, Azure CNI, Entra RBAC, OIDC + workload identity | Needs `AKS_SUBNET_ID` |
| Security | `id-app`, Key Vault (private from the start), `db-password`, PE `pe-<kv>` + private DNS | Secret needs the vault; PE needs vault + subnet |
| RBAC | UAMI: Key Vault Secrets User, Blob Data Contributor, Reader, custom VM Operator role | Needs the principal and resource IDs captured above |
| Governance | "Allowed locations" policy on the RG | — |

### The Key Vault secret: control plane vs data plane

`az keyvault secret set` talks to the vault's own endpoint (data plane). With public access disabled that needs network access to the vault,
plus a data role like Key Vault Secrets Officer, which the playground SPN can't grant itself.

The script instead writes the secret through Azure Resource Manager (control plane), the same way Bicep, ARM and Terraform's `azapi` do:

```bash
az rest --method put \
  --url "https://management.azure.com${KV_ID}/secrets/db-password?api-version=2023-07-01" \
  --body @body.json          # {"properties":{"value":"..."}}, written to a private temp file
```

So the vault is created locked down and stays that way; no open-then-close dance.

---

## 3. `02-deploy-templates.sh`

A reference for the template commands. The same commands deploy Bicep and ARM; only the file changes.
Subscription-scope lines are skipped unless `SUB_SCOPE=true`.

```bash
az deployment group create  -g $RG -f ../bicep/modules/02-storage.bicep -n storage       # default scope = RG
az deployment group what-if -g $RG -f ../bicep/modules/03-network.bicep                  # preview
az deployment group create  -g $RG -p ../bicep/main-rg.bicepparam -n main-rg             # everything, existing RG
az deployment group create  -g $RG -f ../arm/storage.json -p @../arm/storage.parameters.json -n storage
az bicep build     -f ../bicep/main.bicep       # Bicep -> ARM
az bicep decompile -f ../arm/network.json       # ARM -> Bicep
az stack group create -n stack-demo -g $RG -f ../bicep/modules/02-storage.bicep \
  --action-on-unmanage deleteResources --deny-settings-mode none --yes    # deletes what leaves the template
```

For dependency wiring between modules, use `../bicep/deploy.sh` or `../arm/deploy.sh`.

---

## 4. Playground notes

| Item | Behaviour |
|------|-----------|
| Resource group | Reused, never recreated; no subscription rights needed |
| Storage container | `--auth-mode key`: needs only Contributor (`listKeys`) |
| Key Vault | Playground flags drop purge protection and use 7-day retention; secret goes through ARM |
| RBAC, custom role, policy | Skipped with `DEPLOY_RBAC=false` |
| AKS | Off by default (`DEPLOY_AKS=true` to try; quota and size policy may block it) |
| Deployment stacks with `denyDelete` | Needs `deploymentStacks/manageDenySetting/action`, so the script uses `none` |

Clean up: CLI resources aren't in ARM deployment history, so `cleanup.sh` doesn't see them. Delete by name
(`az resource list -g "$RG" --query "[?!starts_with(name,'nautilus')].id" -o tsv | xargs -r -n1 az resource delete --ids`), then
`az keyvault purge -n kv-demo-<hash>` if you need the vault name again.

---

## 5. Imperative vs declarative — when to use which

| | CLI direct (`01`) | Templates (`02`, Bicep, ARM, Terraform) |
|---|---|---|
| Good for | One-off fixes, exploration, learning resource properties | Anything you'll run twice |
| Re-run | Works here because names are stable and creates are PUTs; order and existence checks are on you | Idempotent by design: converges to the same state |
| Preview | None | `what-if` / `plan` |
| Order | You manage it | Dependency graph works it out |
| Drift / history | None | Deployment history or state |
| Clean up | Delete by hand | `deploy.sh destroy`, deployment stacks, or `../bicep/modules/cleanup.sh` |
