# Azure CLI Kit — Azure Landing Zone (Demo)

The same resources as the other kits, two ways with the Azure CLI:

| Script | Style | What it shows |
|--------|-------|---------------|
| `01-direct-create.sh` | **Imperative**: one `az <noun> create` per resource | Exact CLI syntax for RG, storage, VNet/NSG, VM, AKS, identity, Key Vault + PE, RBAC, custom role, policy |
| `02-deploy-templates.sh` | **Declarative**: `az deployment ...` with the Bicep and ARM files | Scope rule, what-if, `bicep build`/`decompile`, deployment stacks, troubleshooting |

Both are reference scripts: read them section by section and run what you need, rather than executing them top to bottom.

---

## 1. Log in

Same service principal as the Bicep kit: [Bicep README section 1](../bicep/README.md#1-log-in-with-the-service-principal-kodekloud-playground).

```bash
cd ValueMomentum/kit/cli
source ../bicep/modules/az-login.sh
```

The scripts start with placeholders (`SUB_ID="<subscription-id>"`, `RG=rg-demo`). Set them to your values first, e.g. `RG=$RG` and `SUB_ID=$ARM_SUBSCRIPTION_ID`.

---

## 2. The CLI pattern

```
az <noun> [<sub-noun>] <verb> -g <rg> -n <name> [-l <region>] --flags
az ... show ... --query id -o tsv          # capture an ID for the next command
```

| Need | Command shape |
|------|---------------|
| Create | `az network vnet create -g $RG -n vnet-demo --address-prefixes 10.0.0.0/16` |
| Child resource | `az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-pe ...` |
| Capture an ID | `VNET_ID=$(az network vnet show -g $RG -n vnet-demo --query id -o tsv)` |
| Assign a role | `az role assignment create --assignee-object-id <oid> --assignee-principal-type ServicePrincipal --role "<name>" --scope <id>` |
| Deploy a template | `az deployment group create -g $RG -f file.bicep` (or `.json`) |

---

## 3. `01-direct-create.sh`, section by section

| Section | Resources | Order matters because |
|---------|-----------|-----------------------|
| Resource group | `rg-demo` | Everything else lives in it |
| Storage | `stdemo$RANDOM` + `data` container | Container is a child of the account |
| Networking | `nsg-web`, `vnet-demo`, `snet-web` / `snet-pe` / `snet-aks` | VM, AKS and PE need subnet IDs |
| VM | `vm01`, no public IP, system-assigned MI | Needs `WEB_SUBNET_ID` |
| AKS | `aks-demo`, Azure CNI, Entra RBAC, OIDC + workload identity | Needs `AKS_SUBNET_ID` |
| Security | `id-app`, Key Vault, secret, PE + private DNS | Secret is seeded **before** public access is disabled |
| RBAC | UAMI grants, VM Reader, custom VM Operator role | Needs the principal IDs captured above |
| Governance | "Allowed locations" policy on the RG | — |

**The Key Vault ordering is the lesson here.** `az keyvault secret set` talks to the vault's data plane, so it needs network access:
create the vault open → grant yourself Secrets Officer → write the secret → lock the vault down → add the private endpoint.
Templates avoid this dance by writing the secret through ARM (see the [Bicep](../bicep/README.md) and [Terraform](../terraform/README.md) kits).

## 4. `02-deploy-templates.sh`

The same commands deploy Bicep and ARM; only the file changes. Highlights:

```bash
az deployment sub create   -l eastus -f ../bicep/modules/01-rg.bicep -p rgName=rg-demo   # targetScope = subscription
az deployment group what-if -g $RG   -f ../bicep/modules/03-network.bicep                 # preview
az deployment group create -g $RG    -f ../arm/storage.json -p @../arm/storage.parameters.json
az bicep build     -f ../bicep/main.bicep       # Bicep -> ARM
az bicep decompile -f ../arm/network.json       # ARM -> Bicep
az stack group create -n stack-demo -g $RG -f ../bicep/modules/02-storage.bicep \
  --action-on-unmanage deleteResources --deny-settings-mode denyDelete   # deletes what leaves the template
```

For the full, playground-ready Bicep flow use `../bicep/deploy.sh` instead.

---

## 5. Playground notes

`01-direct-create.sh` is written for a subscription you own. On an RG-scoped playground SPN:

| Line | Problem | Fix |
|------|---------|-----|
| `az group create` | No subscription rights | Skip it; set `RG` to the lab RG |
| `az storage container create --auth-mode login` | Needs a blob data role | Use `--auth-mode key` |
| `az vm create --size Standard_B2s` | Size may be blocked by policy | `--size Standard_B1s` |
| `az keyvault create --enable-purge-protection true --retention-days 90` | Playground policy | Drop purge protection, `--retention-days 7` |
| `az ad signed-in-user show` | Only works for a user, not a service principal | Use the SPN's object ID (Bicep README section 2.1) |
| `az role assignment create`, `az role definition create`, `az policy assignment create` | Need Owner / User Access Administrator | Skip on the playground |
| `az aks create` | Quota / size policy | Skip unless quota allows |

---

## 6. Imperative vs declarative — when to use which

| | CLI direct (`01`) | Templates (`02`, Bicep, ARM, Terraform) |
|---|---|---|
| Good for | One-off fixes, exploration, learning resource properties | Anything you'll run twice |
| Re-run | Fails or duplicates (`already exists`) unless you script checks | Idempotent: converges to the same state |
| Preview | None | `what-if` / `plan` |
| Order | You manage it | Dependency graph works it out |
| Drift / history | None | Deployment history or state |
| Clean up | Delete by hand | `deploy.sh destroy`, deployment stacks, or `../bicep/modules/cleanup.sh` |
