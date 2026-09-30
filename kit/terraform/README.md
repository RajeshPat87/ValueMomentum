# Terraform Kit — Azure Landing Zone (Demo)

The same footprint as the [Bicep kit](../bicep/README.md) (storage, network, VM, optional AKS, identity, Key Vault with private endpoint, RBAC), written with the `azurerm` provider.
One flat root module. Every run goes through `deploy.sh`, locally and in the [pipeline](../pipelines/README.md).

## Layout

| File | Contains |
|------|----------|
| `providers.tf` | azurerm 4.x, azapi 2.x, random; partial `azurerm` backend (filled in by `deploy.sh`) |
| `variables.tf` | Inputs with validation: `resource_group_name`, `deploy_*` flags, Key Vault policy, `vm_size`, secrets |
| `main.tf` | Existing-or-new resource group, storage account + `data` container |
| `network.tf` | NSG, `vnet-demo` with `snet-web` / `snet-pe` / `snet-aks`, NSG on every subnet |
| `compute.tf` | `vm01` (Ubuntu 24.04, SSH only, system-assigned MI), optional `aks-demo` |
| `security.tf` | UAMI `id-app`, Key Vault (RBAC, private), `db-password` secret, private endpoint + DNS, "Allowed locations" policy |
| `rbac.tf` | UAMI grants (Key Vault Secrets User, Reader, Blob Data Contributor, custom VM Operator role) |
| `outputs.tf` | `rg_name`, `kv_name`, `key_vault_uri`, `stg_name`, `subnet_ids`, `aks_oidc_issuer` |
| `env/dev.tfvars`, `env/prod.tfvars` | Per-environment flags, committed, no secrets (the Terraform version of `.bicepparam`) |
| `bootstrap-state.sh` | Creates the state storage account + container (idempotent) |
| `deploy.sh` | `plan` / `apply` / `destroy` for one environment |
| `terraform.tfvars.example` | Optional local overrides (copy to `terraform.tfvars`, git-ignored) |
| `commands.md` | Terraform command cheat sheet |

---

## 1. Log in and set secrets

Same service principal and secrets as the Bicep kit ([Bicep README sections 1 and 4](../bicep/README.md#1-log-in-with-the-service-principal-kodekloud-playground)):

```bash
cd ValueMomentum/kit/terraform
source ../bicep/modules/az-login.sh      # exports ARM_CLIENT_ID/SECRET/TENANT_ID/SUBSCRIPTION_ID and RG
source ../bicep/modules/set-secrets.sh   # exports SSH_PUBLIC_KEY and DB_PASSWORD
terraform version                        # needs >= 1.6
```

The `azurerm` provider reads the `ARM_*` variables directly, so `az login` alone is not enough for a service principal.
In the pipeline, the same variables are filled with an OIDC token instead of a secret.

---

## 2. Two modes, like `main-rg.bicep` and `main.bicep`

| `RG` env var | Terraform does | Bicep equivalent | Needs |
|--------------|----------------|------------------|-------|
| set (`kml_rg_...`) | Reads the RG with a `data` source and deploys into it | `main-rg.bicep` | RG Contributor |
| unset | Creates `rg-demo-<env>` | `main.bicep` | Subscription rights; also set `TFSTATE_RG` |

`deploy.sh` maps `RG` to `TF_VAR_resource_group_name`. `terraform destroy` never deletes an RG it only read.

### Flags per environment

| Variable | `env/dev.tfvars` (playground) | `env/prod.tfvars` | Bicep flag |
|----------|-------------------------------|-------------------|------------|
| `deploy_vm` | `true` | `true` | `deployVm` |
| `deploy_aks` | `false` | `false` | `deployAks` |
| `deploy_rbac` | `false` | `true` | `deployRbac` |
| `kv_purge_protection` | `false` | `true` (permanent) | `kvPurgeProtection` |
| `kv_soft_delete_days` | `7` | `90` | `kvSoftDeleteDays` |
| `vm_size` | `Standard_B1s` | `Standard_B1s` | `vmSize` |

To change a flag, edit the env file. It is passed with `-var-file`, so it wins over `terraform.tfvars` and `TF_VAR_*`.
Secrets are never in these files: `SSH_PUBLIC_KEY` and `DB_PASSWORD` arrive as `TF_VAR_ssh_public_key` / `TF_VAR_db_password`.

---

## 3. Remote state

Terraform keeps what it created in a state file. This kit stores it in Azure Blob Storage, one key per environment:

```
<TFSTATE_ACCOUNT>/tfstate/dev.tfstate
<TFSTATE_ACCOUNT>/tfstate/prod.tfstate
```

Create the account once per RG (the pipeline runs this before every plan; re-running is harmless):

```bash
./bootstrap-state.sh               # creates sttf<hash> in $RG + container tfstate
./bootstrap-state.sh --name-only   # just print the account name
```

| Setting | Default | Override |
|---------|---------|----------|
| Resource group | `$RG` | `TFSTATE_RG` |
| Account name | `sttf` + 12 chars of sha256(subscription/RG), stable per RG | `TFSTATE_ACCOUNT` |
| Container | `tfstate` | `TFSTATE_CONTAINER` |
| Auth | Account key (`listKeys`, needs only Contributor) | `TFSTATE_AZUREAD_AUTH=true` (needs Storage Blob Data Contributor) |

Entra ID auth is the better design, but the playground SPN can't grant itself the data role, so key auth is the default.

---

## 4. Deploy

```bash
./deploy.sh plan  dev     # init + plan -> ./tfplan   exit 0 = no changes, 2 = changes, 1 = error
./deploy.sh apply dev     # applies exactly ./tfplan, then prints outputs
```

`apply` refuses to run without a saved plan, so what you reviewed is what gets applied.
Switching between `dev` and `prod` is safe: every run does `terraform init -reconfigure` with that environment's state key.

What `plan` shows:

| Symbol | Meaning |
|--------|---------|
| `+` | create |
| `~` | update in place |
| `-/+` | destroy and recreate (read the reason: `# forces replacement`) |
| `-` | destroy |
| `<=` | read a data source (the existing RG) |

---

## 5. Verify and troubleshoot

```bash
terraform output                           # rg_name, kv_name, stg_name, subnet_ids ...
terraform state list                       # everything Terraform manages
az resource list -g "$RG" --query "[?!starts_with(name,'nautilus')].{Name:name, Type:type}" -o table
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Backend initialization required` | Ran `terraform plan` directly | Use `./deploy.sh`, it runs `init` with the backend settings |
| `StorageAccountNotFound` / 404 at init | State account not created | `./bootstrap-state.sh` |
| `AuthorizationFailed ... listKeys` at init | Deployer can't read the state account keys | Grant Contributor on the state RG, or use `TFSTATE_AZUREAD_AUTH=true` with a data role |
| `AuthorizationFailed ... roleAssignments/write` | `deploy_rbac = true` without Owner / User Access Administrator | `deploy_rbac = false` in the env file |
| `RequestDisallowedByPolicy` on Key Vault | Playground: 7-day soft delete, no purge protection | Already set in `env/dev.tfvars` |
| `VaultAlreadyExists` | A deleted vault keeps its name for the retention period | New `random_string` suffix: `terraform apply -replace=random_string.sfx` (recreates the named resources) |
| `Error acquiring the state lock` | A previous run died while holding the lease | `terraform force-unlock <lock-id>` |
| `Error ensuring Resource Providers are registered` | Provider auto-registration | Disabled in `providers.tf`; on a fresh subscription run `az provider register -n <namespace>` once |
| Plan wants to change `enable_rbac_authorization` | Old provider name | This kit uses `rbac_authorization_enabled` |

---

## 6. Clean up

```bash
./deploy.sh destroy dev    # interactive; removes everything in dev.tfstate
```

The state storage account is not managed by Terraform (it has to exist before Terraform runs). Delete it by hand when you're done:

```bash
az storage account delete -g "$RG" -n "$(./bootstrap-state.sh --name-only)" --yes
```

---

## 7. Bicep ↔ Terraform, side by side

| Concept | Bicep kit | Terraform kit |
|---------|-----------|---------------|
| Entry point | `main-rg.bicep` / `main.bicep` | root module (all `.tf` files) |
| Per-env values | `.bicepparam` | `env/<env>.tfvars` |
| Secrets in | `readEnvironmentVariable()` | `TF_VAR_*` + `sensitive = true` |
| Preview | `what-if` | `plan` |
| Record of what exists | ARM deployment history | state file |
| Optional resource | `module x = if (flag)` | `count = var.flag ? 1 : 0` |
| Existing resource | `existing` keyword | `data` source |
| Unique names | `uniqueString(resourceGroup().id)` | `random_string` suffix |
| Input rules | `@allowed`, `@minValue` | `validation {}` blocks |
| Key Vault secret | ARM resource `vaults/secrets` | `azapi_resource` on the same ARM type (not `azurerm_key_vault_secret`) |
| Delete what's gone from code | Deployment stacks, or Complete mode | Built in: removed from code = destroyed on apply |

**Why azapi for the secret:** `azurerm_key_vault_secret` writes to the vault's own endpoint, which is unreachable with public access disabled.
`azapi_resource` writes through the ARM control plane like Bicep does, so a hosted pipeline agent can seed the secret into a private vault.

**Design choices worth saying out loud:** existing-RG mode for least privilege, all authorization writes behind one flag, secure defaults with the playground relaxations in a named env file, saved plan applied as-is, provider versions pinned by the lock file the pipeline carries from plan to apply.
