#!/usr/bin/env bash
# deploy.sh <action> <target> — one entry point for local runs AND the pipeline (kit/pipelines/templates/bicep-deploy.yml)
#
#   action : validate | what-if | create
#   target : main-rg   all modules into an existing RG   (main-rg.bicepparam)
#            main      RG + all modules, subscription scope (main.bicepparam)
#            storage | network | vm | aks | security | rbac | mini   one module (README Option A)
#
# Env: RG (every target except main), LOCATION (main only, default eastus),
#      SSH_PUBLIC_KEY, DB_PASSWORD (source ./modules/set-secrets.sh locally),
#      EXTRA_PARAMS (optional "name=value name=value" overrides)
#
# Single modules read their inputs from earlier deployments (vm needs network, rbac needs security + storage).
# The deployment name is the target, so cleanup.sh can find everything this script created.
set -euo pipefail
cd "$(dirname "$0")"

usage() { sed -n '2,9p' "$0" >&2; exit 2; }
action=${1:-}; target=${2:-}
case "$action" in validate|what-if|create) ;; *) usage ;; esac

# output <deployment> <name>: read an output from an earlier deployment in $RG
output() {
  az deployment group show -g "$RG" -n "$1" --query "properties.outputs.$2.value" -o tsv 2>/dev/null |
    grep . || { echo "ERROR: no output '$2' from deployment '$1' in $RG. Deploy target '$1' first." >&2; exit 1; }
}

module=''; params=()
case "$target" in
  main-rg)  src=(-p main-rg.bicepparam) ;;
  main)     src=(-p main.bicepparam) ;;
  storage)  module=02-storage ;;
  network)  module=03-network ;;
  vm)       module=04-vm;       params=(subnetId="$(output network webSubnetId)" sshPublicKey="${SSH_PUBLIC_KEY:?}") ;;
  aks)      module=05-aks;      params=(subnetId="$(output network aksSubnetId)") ;;
  security) module=07-security; params=(vnetId="$(output network vnetId)" peSubnetId="$(output network peSubnetId)"
                                        dbPassword="${DB_PASSWORD:-}") ;;
  rbac)     module=06-rbac;     params=(principalId="$(output security uamiPrincipalId)" stgName="$(output storage stgName)") ;;
  mini)     module=mini;        params=(sshPublicKey="${SSH_PUBLIC_KEY:?}") ;;
  *)        usage ;;
esac

if [ "$target" = main ]; then
  at=(sub -l "${LOCATION:-eastus}"); show=(sub)
else
  : "${RG:?export RG=<resource group> first}"
  at=(group -g "$RG"); show=(group -g "$RG")
fi
[ -n "$module" ] && src=(-f "modules/$module.bicep")

args=("${src[@]}")
[ ${#params[@]} -gt 0 ] && args+=(-p "${params[@]}")
read -ra extra <<< "${EXTRA_PARAMS:-}"
[ ${#extra[@]} -gt 0 ] && args+=(-p "${extra[@]}")

echo "==> az deployment ${at[0]} $action  target=$target"
case "$action" in
  validate) az deployment "${at[@]}" validate -n "$target" "${args[@]}" -o none && echo "valid" ;;
  what-if)  az deployment "${at[@]}" what-if  -n "$target" "${args[@]}" ;;
  create)   az deployment "${at[@]}" create   -n "$target" "${args[@]}" -o none
            az deployment "${show[@]}" show -n "$target" --query properties.outputs -o json ;;
esac
