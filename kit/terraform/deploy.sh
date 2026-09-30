#!/usr/bin/env bash
# deploy.sh <action> <env> — one entry point for local runs AND the pipeline (kit/pipelines/templates/terraform-deploy.yml)
#
#   action : plan     init + plan -> ./tfplan   (exit 0 no changes, 2 changes, 1 error)
#            apply    init + apply ./tfplan     (run plan first; the pipeline downloads it)
#            destroy  init + destroy            (interactive locally)
#   env    : dev | prod   -> env/<env>.tfvars, state key <env>.tfstate
#
# Env: RG             existing RG to deploy into (unset = Terraform creates rg-demo-<env>)
#      SSH_PUBLIC_KEY, DB_PASSWORD           (source ../bicep/modules/set-secrets.sh locally)
#      TFSTATE_RG, TFSTATE_ACCOUNT           (defaults: $RG and the name bootstrap-state.sh derives)
#      TFSTATE_CONTAINER (tfstate), TFSTATE_AZUREAD_AUTH (false = account key, needs only Contributor)
#      ARM_* auth: az-login.sh exports a client secret locally; the pipeline exports OIDC
set -euo pipefail
cd "$(dirname "$0")"

usage() { sed -n '2,15p' "$0" >&2; exit 2; }
action=${1:-}; env=${2:-}
case "$action" in plan|apply|destroy) ;; *) usage ;; esac
[ -f "env/$env.tfvars" ] || usage

export ARM_SUBSCRIPTION_ID=${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}
export TF_VAR_subscription_id=$ARM_SUBSCRIPTION_ID
export TF_VAR_resource_group_name=${RG:-}
export TF_VAR_ssh_public_key=${SSH_PUBLIC_KEY:?source set-secrets.sh or set SSH_PUBLIC_KEY}
export TF_VAR_db_password=${DB_PASSWORD:-}

export TFSTATE_RG=${TFSTATE_RG:-${RG:-}}
: "${TFSTATE_RG:?set TFSTATE_RG when RG is unset (Terraform creates the RG, state must live elsewhere)}"
TFSTATE_ACCOUNT=${TFSTATE_ACCOUNT:-$(./bootstrap-state.sh --name-only)}

echo "==> terraform $action  env=$env  rg=${RG:-<create rg-demo-$env>}  state=$TFSTATE_ACCOUNT/$env.tfstate"
terraform init -input=false -reconfigure \
  -backend-config="resource_group_name=$TFSTATE_RG" \
  -backend-config="storage_account_name=$TFSTATE_ACCOUNT" \
  -backend-config="container_name=${TFSTATE_CONTAINER:-tfstate}" \
  -backend-config="key=$env.tfstate" \
  -backend-config="use_azuread_auth=${TFSTATE_AZUREAD_AUTH:-false}"

case "$action" in
  plan)    rc=0; terraform plan -input=false -var-file="env/$env.tfvars" -detailed-exitcode -out=tfplan || rc=$?
           exit "$rc" ;;
  apply)   [ -f tfplan ] || { echo "ERROR: no ./tfplan. Run: ./deploy.sh plan $env" >&2; exit 1; }
           terraform apply -input=false tfplan
           terraform output ;;
  destroy) terraform destroy -input=false -var-file="env/$env.tfvars" ;;
esac
