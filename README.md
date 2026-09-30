# ValueMomentum — Azure IaC Kit

The same Azure resources (resource group, storage, network, VM, AKS, RBAC, Key Vault)
built four ways, so each approach can be compared side by side:

| Folder | Approach |
|---|---|
| `kit/cli/` | Azure CLI — direct `az ... create` and template deployments |
| `kit/arm/` | ARM JSON templates (+ parameter files) |
| `kit/arm-built/` | ARM JSON compiled from the Bicep modules (`az bicep build`) |
| `kit/bicep/` | Bicep — `main.bicep` orchestrator + numbered `modules/` |
| `kit/terraform/` | Terraform (azurerm) equivalents |
| `kit/pipelines/` | Azure DevOps: one `azure-pipelines.yml` (choose Bicep or Terraform) + templates |

See [`kit/README.md`](kit/README.md) for the full walkthrough and
[`kit/bicep/README.md`](kit/bicep/README.md) for login and deploy commands.

## Credentials

Nothing secret is committed. Locally create:

- `kit/bicep/modules/az-login.sh` — service-principal login (git-ignored)
- `kit/terraform/terraform.tfvars` — optional local overrides, copy from `terraform.tfvars.example` (git-ignored).
  Per-environment flags are committed in `kit/terraform/env/<env>.tfvars`; secrets come from env vars.
