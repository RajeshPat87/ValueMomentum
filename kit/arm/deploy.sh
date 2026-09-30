#!/usr/bin/env bash
# deploy.sh <action> <target> — deploy the hand-written ARM templates in dependency order (mirror of ../bicep/deploy.sh)
#
#   action : validate | what-if | create
#   target : rg (subscription scope) | storage | network | vm | keyvault | rbac
#
# Env: RG (resource group targets), RG_NAME + LOCATION (rg target; defaults rg-demo / eastus),
#      SSH_PUBLIC_KEY (vm), DB_PASSWORD (keyvault, optional),
#      EXTRA_PARAMS (optional "name=value" or "@file.json" overrides)
#      Playground: EXTRA_PARAMS=@keyvault.playground.parameters.json ./deploy.sh create keyvault
#
# vm and keyvault read network outputs; rbac reads keyvault + storage outputs. The deployment name is the target.
set -euo pipefail
cd "$(dirname "$0")"

usage() { sed -n '2,11p' "$0" >&2; exit 2; }
action=${1:-}; target=${2:-}
case "$action" in validate|what-if|create) ;; *) usage ;; esac

# output <deployment> <name>: read an output from an earlier deployment in $RG
output() {
  az deployment group show -g "$RG" -n "$1" --query "properties.outputs.$2.value" -o tsv 2>/dev/null |
    grep . || { echo "ERROR: no output '$2' from deployment '$1' in $RG. Deploy target '$1' first." >&2; exit 1; }
}

params=()
case "$target" in
  rg)       params=(rgName="${RG_NAME:-rg-demo}" location="${LOCATION:-eastus}") ;;
  storage)  params=(@storage.parameters.json) ;;
  network)  ;;
  vm)       params=(subnetId="$(output network webSubnetId)" sshPublicKey="${SSH_PUBLIC_KEY:?source set-secrets.sh first}") ;;
  keyvault) params=(vnetId="$(output network vnetId)" peSubnetId="$(output network peSubnetId)" dbPassword="${DB_PASSWORD:-}") ;;
  rbac)     params=(principalId="$(output keyvault uamiPrincipalId)" stgName="$(output storage stgName)") ;;
  *)        usage ;;
esac

if [ "$target" = rg ]; then
  at=(sub -l "${LOCATION:-eastus}"); show=(sub)
else
  : "${RG:?export RG=<resource group> first}"
  at=(group -g "$RG"); show=(group -g "$RG")
fi

args=(-f "$target.json")
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
