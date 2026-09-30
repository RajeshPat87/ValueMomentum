# ValueMomentum — Azure IaC Kit

The same Azure footprint (resource group, storage, network, VM, optional AKS, managed identity, private Key Vault, RBAC)
built four ways, plus the pipelines that deploy it, so each approach can be compared side by side.

## Approaches

| Approach | Folder | Runbook | Style | Best for |
|----------|--------|---------|-------|----------|
| **Bicep** | `kit/bicep/` | [kit/bicep/README.md](kit/bicep/README.md) | Declarative, compiled to ARM | The main path: modules, feature flags, `deploy.sh` for main files or single modules |
| **Terraform** | `kit/terraform/` | [kit/terraform/README.md](kit/terraform/README.md) | Declarative, state file | Same resources with azurerm + azapi, remote state, `deploy.sh plan/apply` |
| **ARM JSON** | `kit/arm/`, `kit/arm-built/` | [kit/arm/README.md](kit/arm/README.md) | Declarative, raw engine format | Seeing what Bicep compiles to; parameter files, Key Vault references, `deploy.sh` per file |
| **Azure CLI** | `kit/cli/` | [kit/cli/README.md](kit/cli/README.md) | Imperative commands | One-off creation with the same flags as Bicep, learning resource properties, deploying templates |
| **Pipelines** | `kit/pipelines/` | [kit/pipelines/README.md](kit/pipelines/README.md) | Azure DevOps YAML | One `azure-pipelines.yml`: pick Bicep or Terraform, validate → dev → prod |

[`kit/README.md`](kit/README.md) is the long-form interview notepad: mental models and every file in one document.

## Same resource, four ways

| Resource | Bicep | Terraform | ARM | CLI |
|----------|-------|-----------|-----|-----|
| Resource group | `modules/01-rg.bicep`, `main.bicep` | `main.tf` (created or existing) | `rg.json` | `az group create` |
| Storage | `modules/02-storage.bicep` | `main.tf` | `storage.json` | `az storage account create` |
| VNet, subnets, NSG | `modules/03-network.bicep` | `network.tf` | `network.json` | `az network vnet create` |
| VM | `modules/04-vm.bicep` | `compute.tf` | `vm.json` | `az vm create` |
| AKS | `modules/05-aks.bicep` | `compute.tf` | — | `az aks create` |
| RBAC + custom role | `modules/06-rbac.bicep` | `rbac.tf` | `rbac.json` | `az role assignment create` |
| Identity, Key Vault, PE | `modules/07-security.bicep` | `security.tf` | `keyvault.json` | `az identity` / `keyvault` / `network private-endpoint` |

## Quick start (KodeKloud playground)

```bash
cd kit/bicep
# create modules/az-login.sh with the lab credentials first (Bicep README section 1)
source modules/az-login.sh && source modules/set-secrets.sh

./deploy.sh what-if main-rg && ./deploy.sh create main-rg                                  # Bicep
cd ../terraform && ./bootstrap-state.sh && ./deploy.sh plan dev && ./deploy.sh apply dev   # Terraform
```

Run one tool per resource group: both use the same fixed names (`vnet-demo`, `vm01`, ...), so the second would take over the first one's resources.

## Credentials

Nothing secret is committed. Locally create:

- `kit/bicep/modules/az-login.sh` — service-principal login (git-ignored)
- `kit/terraform/terraform.tfvars` — optional local overrides, copy from `terraform.tfvars.example` (git-ignored).
  Per-environment flags are committed in `kit/terraform/env/<env>.tfvars`; secrets come from env vars.

In the pipeline, credentials come from a workload-identity service connection and secrets from a variable group (see the [pipelines README](kit/pipelines/README.md)).
