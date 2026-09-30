#!/usr/bin/env bash
# cleanup.sh - delete ONLY resources created by this kit's deployments
# ./cleanup.sh (dry run) | ./cleanup.sh --yes | ./cleanup.sh --yes --purge
set -uo pipefail
: "${RG:?export RG=<resource group> first}"
EXECUTE=false; PURGE=false
for a in "$@"; do case "$a" in --yes) EXECUTE=true ;; --purge) PURGE=true ;; esac; done

DEPLOYMENTS=(vm security network storage aks rbac mini main-rg)

IDS=$(for d in "${DEPLOYMENTS[@]}"; do
  az deployment group show -g "$RG" -n "$d" --query 'properties.outputResources[].id' -o tsv 2>/dev/null
done | sort -u)

DISKS=$(echo "$IDS" | grep -iE '/providers/Microsoft\.Compute/virtualMachines/[^/]+$' | while read -r vm; do
  az vm show --ids "$vm" --query 'storageProfile.osDisk.managedDisk.id' -o tsv 2>/dev/null
done)
IDS=$(printf '%s\n%s\n' "$IDS" "$DISKS" | grep -v '^$' | grep -vi '/nautilus' | sort -u)
[ -z "$IDS" ] && { echo "Nothing found from kit deployments in $RG."; exit 0; }

ORDER=(
  'Microsoft.Compute/virtualMachines'
  'Microsoft.Compute/disks'
  'Microsoft.Network/networkInterfaces'
  'Microsoft.ContainerService/managedClusters'
  'Microsoft.Network/privateEndpoints'
  'Microsoft.Network/privateDnsZones/[^/]+/virtualNetworkLinks'
  'Microsoft.Network/privateDnsZones'
  'Microsoft.KeyVault/vaults'
  'Microsoft.ManagedIdentity/userAssignedIdentities'
  'Microsoft.Network/virtualNetworks'
  'Microsoft.Network/networkSecurityGroups'
  'Microsoft.Storage/storageAccounts'
)

echo "Resource group: $RG"; $EXECUTE && echo "Mode: DELETE" || echo "Mode: DRY RUN (add --yes to delete)"; echo
for t in "${ORDER[@]}"; do
  echo "$IDS" | grep -iE "/providers/${t}/[^/]+$" | while read -r id; do
    [ -z "$id" ] && continue; name=${id##*/}
    if $EXECUTE; then
      echo "deleting  $name"; az resource delete --ids "$id" -o none || echo "  FAILED $name"
      if $PURGE && [[ "$id" == *"/Microsoft.KeyVault/vaults/"* ]]; then
        echo "purging   $name"; az keyvault purge -n "$name" -o none || echo "  purge FAILED"
      fi
    else
      echo "would delete  $name"
    fi
  done
done

if $EXECUTE; then
  for d in "${DEPLOYMENTS[@]}"; do az deployment group delete -g "$RG" -n "$d" --no-wait 2>/dev/null; done
fi
echo; echo "Remaining (non-lab) resources:"
az resource list -g "$RG" --query '[?!starts_with(name, `nautilus`)].{Name:name, Type:type}' -o table
