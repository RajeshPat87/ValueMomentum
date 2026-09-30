# Pipelines — Azure DevOps for the Bicep and Terraform kits

One pipeline, `azure-pipelines.yml`. When you queue a run you pick the tool (and for Bicep, the target).
Each tool has two templates, and every deploy step calls the same `deploy.sh` you run locally, so a pipeline run and a laptop run do the same thing.

```
pipelines/
├── azure-pipelines.yml          entry point: parameters tool + bicepTarget
├── templates/
│   ├── bicep-validate.yml       build + lint every .bicep, publish artifact
│   ├── bicep-deploy.yml         per env: validate + what-if → approval → create   (../bicep/deploy.sh)
│   ├── terraform-validate.yml   fmt + validate, no backend
│   └── terraform-deploy.yml     per env: plan → approval → apply saved plan       (../terraform/deploy.sh)
└── examples/                    syntax reference only, not used by the pipeline
```

## Flow

```
 tool = bicep                                         tool = terraform
 ─────────────                                        ────────────────
 bicep_validate   (no Azure)                          terraform_validate   (no Azure)
      │                                                     │
 bicep_dev    preview: validate + what-if              terraform_dev    plan (+ bootstrap state)
      │       deploy : ⏸ env "dev" → create                 │           apply: ⏸ env "dev" → apply tfplan
      │                                                     │                  (skipped when no changes)
 bicep_prod   same, only on main                       terraform_prod   same, only on main
```

| Trigger | What runs |
|---------|-----------|
| Push to `main` touching `kit/bicep/` or `kit/pipelines/` | Defaults: `tool=bicep`, `bicepTarget=main-rg`, dev then prod |
| Pull request to `main` | Validate + dev preview only (what-if); deploy jobs skip on `Build.Reason == PullRequest` |
| Manual run | Any tool / target. Terraform runs are always started manually |

---

## 1. One-time setup in Azure DevOps

Everything per environment follows one naming convention, so the YAML never hard-codes names per stage.

| Thing | dev | prod | Notes |
|-------|-----|------|-------|
| Service connection (Azure Resource Manager) | `sc-azure-dev` | `sc-azure-prod` | Use **workload identity federation**: no secret to rotate. RG Contributor is enough for `main-rg` and Terraform existing-RG mode |
| Variable group | `vg-iac-dev` | `vg-iac-prod` | Contents below |
| Environment | `dev` | `prod` | Add **Approvals and checks** on `prod` |

### Variable group contents

| Variable | Used by | Secret? | Example |
|----------|---------|---------|---------|
| `RG` | Bicep (all targets except `main`), Terraform existing-RG mode | no | `kml_rg_main-abc123` |
| `SSH_PUBLIC_KEY` | Bicep `.bicepparam`, Terraform `TF_VAR_ssh_public_key` | no | `ssh-rsa AAAA...` |
| `DB_PASSWORD` | Key Vault secret `db-password` | **yes** | — |
| `EXTRA_PARAMS` | Bicep only, optional | no | `deployVm=false kvSoftDeleteDays=7` |
| `TFSTATE_RG`, `TFSTATE_ACCOUNT` | Terraform only, optional | no | defaults: `$RG` and the derived `sttf<hash>` name |

Secret variables are **not** visible to scripts automatically. The templates map every variable through `env:` explicitly, which is why they work.

### Create the pipeline

1. **Pipelines → New pipeline →** your repo (GitHub or Azure Repos) **→ Existing Azure Pipelines YAML file**.
2. Path: `/kit/pipelines/azure-pipelines.yml`. Save.
3. First run: DevOps asks you to **authorize** the pipeline to use the service connection, variable group and environment. Approve once per resource.

---

## 2. Running it

**Run pipeline** shows two parameters:

| Parameter | Values | Meaning |
|-----------|--------|---------|
| IaC tool | `bicep`, `terraform` | Which side runs |
| Bicep target | `main-rg` | All modules into the existing RG ([Bicep Option B](../bicep/README.md#option-b--one-shot-into-the-existing-rg-main-rgbicep--main-rgbicepparam)) |
| | `main` | RG + all modules, subscription scope (Option C) |
| | `storage`, `network`, `vm`, `aks`, `security`, `rbac`, `mini` | One module (Option A). `vm`/`aks`/`security` need `network` first; `rbac` needs `security` and `storage` |

Terraform flags per environment come from `kit/terraform/env/<env>.tfvars`; Bicep flags from `main-rg.bicepparam` plus `EXTRA_PARAMS`.

### What each stage proves

| Gate | Bicep | Terraform |
|------|-------|-----------|
| 1. Static (no Azure) | `az bicep build` + `lint` on every file | `terraform fmt -check`, `validate` |
| 2. Preflight | `deploy.sh validate <target>` | `terraform plan` (provider + API checks) |
| 3. Diff | `deploy.sh what-if <target>` | same `plan`, saved as `tfplan` |
| Approval | ADO environment | ADO environment |
| 4. Deploy | `deploy.sh create <target>` | `deploy.sh apply` of the saved plan, with the same provider lock file |

Deploy jobs are `deployment:` jobs, so the environment records every run (who, what, when) and gates it.
Deployment jobs don't check out code: Bicep deploys the artifact published by `bicep_validate`; Terraform checks out and downloads the plan artifact.

---

## 3. Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `BCP427: Environment variable "SSH_PUBLIC_KEY" does not exist` | Variable missing from `vg-iac-<env>` | Add it |
| Key Vault secret empty / script sees `$(DB_PASSWORD)` literally | Secret not mapped, or not defined in the group | Define it in the group; templates already map it via `env:` |
| `There was a resource authorization issue` | First use of a connection / group / environment | Open the run and **Permit** |
| `AuthorizationFailed ... Microsoft.Resources/deployments/write` at subscription | `bicepTarget=main` with an RG-scoped connection | Use `main-rg` |
| `ERROR: no output 'webSubnetId' from deployment 'network'` | Deployed a module before its prerequisite | Run target `network` first |
| Terraform apply skipped | Plan found no changes | Expected (`hasChanges=false`) |
| Terraform `Error acquiring the state lock` | Earlier run cancelled mid-apply | `terraform force-unlock <id>` locally, see [Terraform README](../terraform/README.md#5-verify-and-troubleshoot) |
| Prod stage missing | Run was not from `main` | Prod is added only for `refs/heads/main` |

---

## 4. `examples/` — syntax reference

Stand-alone files for interview questions on YAML pipeline syntax. They are not wired to the kit.

| File | Shows |
|------|-------|
| `single-job.yml` | Root keys (Trigger, Resources, Variables, Pool, Steps), one job |
| `parallel-jobs-matrix.yml` | Parallel jobs, matrix strategy, fan-in with `dependsOn`, publishing an artifact |
| `multi-stage-approvals.yml` | Stages → jobs → steps, variable groups, deployment jobs, environment approvals |
| `cross-repo-templates.yml` | Templates from another repo (`@templates`), pipeline resource triggers |
| `extends-governance.yml` | `extends:` a required template for governance |
| `dependencies-and-outputs.yml` | Output variables across jobs and stages, conditions, fan-out / fan-in |

Expression cheat sheet: `${{ }}` compile time (parameters, template `if`) · `$[ ]` runtime (conditions, dependencies) · `$( )` macro, replaced just before a task runs.
