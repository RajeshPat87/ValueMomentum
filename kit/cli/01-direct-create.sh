#!/usr/bin/env bash
# DIRECT creation (no template). Pattern: az <noun> [<sub>] <verb> -g -n -l --flags ; capture: --query id -o tsv
# Same resources and flags as the Bicep kit. Secure defaults; playground run:
#   source ../bicep/modules/az-login.sh && source ../bicep/modules/set-secrets.sh
#   DEPLOY_RBAC=false KV_PURGE_PROTECTION=false KV_SOFT_DELETE_DAYS=7 ./01-direct-create.sh
set -euo pipefail

# ---------- Inputs (env overrides, same meaning as the Bicep flags) ----------
RG=${RG:-rg-demo}                             # existing RG is reused, otherwise created
LOC=${LOC:-eastus}
VM_SIZE=${VM_SIZE:-Standard_B1s}
DEPLOY_VM=${DEPLOY_VM:-true}
DEPLOY_AKS=${DEPLOY_AKS:-false}
DEPLOY_RBAC=${DEPLOY_RBAC:-true}              # role assignments, custom role, policy (needs Owner / UAA)
KV_PURGE_PROTECTION=${KV_PURGE_PROTECTION:-true}
KV_SOFT_DELETE_DAYS=${KV_SOFT_DELETE_DAYS:-90}
: "${SSH_PUBLIC_KEY:?source ../bicep/modules/set-secrets.sh first}"
DB_PASSWORD=${DB_PASSWORD:-}

SUB_ID=${ARM_SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}
az account set --subscription "$SUB_ID"
SFX=$(printf '%s/%s' "$SUB_ID" "$RG" | sha256sum | cut -c1-6)   # stable per RG, so a re-run reuses names

# ---------- Resource group ----------
az group show -n "$RG" -o none 2>/dev/null || az group create -n "$RG" -l "$LOC" --tags env=dev -o none
RG_ID=$(az group show -n "$RG" --query id -o tsv)
LOC=$(az group show -n "$RG" --query location -o tsv)        # an existing RG keeps its region

# ---------- Storage ----------
STG="stdemo$SFX"
az storage account create -g "$RG" -n "$STG" -l "$LOC" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false -o none
az storage container create --account-name "$STG" -n data --auth-mode key -o none   # key: no data-plane role needed
STG_ID=$(az storage account show -g "$RG" -n "$STG" --query id -o tsv)

# ---------- Networking ----------
az network nsg create -g "$RG" -n nsg-web -o none
az network nsg rule create -g "$RG" --nsg-name nsg-web -n Allow-443-In \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --destination-port-ranges 443 -o none

az network vnet create -g "$RG" -n vnet-demo --address-prefixes 10.0.0.0/16 \
  --subnet-name snet-web --subnet-prefixes 10.0.1.0/24 --network-security-group nsg-web -o none
az network vnet subnet create -g "$RG" --vnet-name vnet-demo -n snet-pe  --address-prefixes 10.0.2.0/24 --network-security-group nsg-web -o none
az network vnet subnet create -g "$RG" --vnet-name vnet-demo -n snet-aks --address-prefixes 10.0.4.0/22 --network-security-group nsg-web -o none

VNET_ID=$(az network vnet show -g "$RG" -n vnet-demo --query id -o tsv)
WEB_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name vnet-demo -n snet-web --query id -o tsv)
AKS_SUBNET_ID=$(az network vnet subnet show -g "$RG" --vnet-name vnet-demo -n snet-aks --query id -o tsv)

# Peering (needs both directions)
# az network vnet peering create -g $RG -n demo-to-hub --vnet-name vnet-demo --remote-vnet "$HUB_VNET_ID" --allow-vnet-access --allow-forwarded-traffic

# ---------- Compute: VM ----------
if [ "$DEPLOY_VM" = true ]; then
  az vm create -g "$RG" -n vm01 --image Ubuntu2404 --size "$VM_SIZE" --storage-sku StandardSSD_LRS \
    --admin-username azureuser --ssh-key-values "$SSH_PUBLIC_KEY" \
    --subnet "$WEB_SUBNET_ID" --public-ip-address "" --nsg "" \
    --assign-identity -o none
fi

# ---------- Compute: AKS ----------
if [ "$DEPLOY_AKS" = true ]; then
  az aks create -g "$RG" -n aks-demo --node-count 2 --node-vm-size Standard_D4s_v5 \
    --network-plugin azure --network-policy azure --vnet-subnet-id "$AKS_SUBNET_ID" \
    --service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10 \
    --enable-managed-identity --enable-aad --enable-azure-rbac \
    --enable-oidc-issuer --enable-workload-identity --ssh-key-value "$SSH_PUBLIC_KEY" -o none
  az aks get-credentials -g "$RG" -n aks-demo
fi

# ---------- Security: identity + Key Vault + private endpoint ----------
az identity create -g "$RG" -n id-app -o none
UAMI_PID=$(az identity show -g "$RG" -n id-app --query principalId -o tsv)

KV="kv-demo-$SFX"
PURGE=(); [ "$KV_PURGE_PROTECTION" = true ] && PURGE=(--enable-purge-protection true)   # can't be set to false, only omitted
az keyvault create -g "$RG" -n "$KV" -l "$LOC" \
  --enable-rbac-authorization true --retention-days "$KV_SOFT_DELETE_DAYS" "${PURGE[@]}" \
  --public-network-access Disabled --default-action Deny --bypass AzureServices -o none
KV_ID=$(az keyvault show -n "$KV" --query id -o tsv)

# Secret through the ARM control plane (like Bicep / Terraform azapi): works with the vault already private
# and needs no data-plane role. 'az keyvault secret set' would need network access + Secrets Officer.
if [ -n "$DB_PASSWORD" ]; then
  v=${DB_PASSWORD//\\/\\\\}; v=${v//\"/\\\"}                  # JSON-escape \ and "
  BODY=$(umask 077; mktemp)                                   # body in a private file, not on the command line
  printf '{"properties":{"value":"%s"}}' "$v" > "$BODY"
  az rest --method put --url "https://management.azure.com${KV_ID}/secrets/db-password?api-version=2023-07-01" \
    --body @"$BODY" -o none
  rm -f "$BODY"
fi

az network private-endpoint create -g "$RG" -n "pe-$KV" --vnet-name vnet-demo --subnet snet-pe \
  --private-connection-resource-id "$KV_ID" --group-id vault --connection-name psc-kv -o none
az network private-dns zone create -g "$RG" -n privatelink.vaultcore.azure.net -o none
az network private-dns link vnet create -g "$RG" -n link-vnet \
  --zone-name privatelink.vaultcore.azure.net --virtual-network "$VNET_ID" --registration-enabled false -o none
az network private-endpoint dns-zone-group create -g "$RG" --endpoint-name "pe-$KV" -n default \
  --private-dns-zone privatelink.vaultcore.azure.net --zone-name kv -o none

# ---------- RBAC (same grants as 06-rbac.bicep + kvRole in 07-security.bicep) ----------
if [ "$DEPLOY_RBAC" = true ]; then
  for grant in "Key Vault Secrets User|$KV_ID" "Storage Blob Data Contributor|$STG_ID" "Reader|$RG_ID"; do
    az role assignment create --assignee-object-id "$UAMI_PID" --assignee-principal-type ServicePrincipal \
      --role "${grant%%|*}" --scope "${grant#*|}" -o none
  done

  ROLE_FILE=$(mktemp)
  cat > "$ROLE_FILE" <<JSON
{
  "Name": "VM Operator ($RG)",
  "Description": "Read, start and restart VMs",
  "Actions": [
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/restart/action"
  ],
  "NotActions": [],
  "AssignableScopes": ["$RG_ID"]
}
JSON
  az role definition list --name "VM Operator ($RG)" --query '[0].id' -o tsv | grep -q . ||
    az role definition create --role-definition @"$ROLE_FILE" -o none
  rm -f "$ROLE_FILE"
  az role assignment create --assignee-object-id "$UAMI_PID" --assignee-principal-type ServicePrincipal \
    --role "VM Operator ($RG)" --scope "$RG_ID" -o none
  az role assignment list --assignee "$UAMI_PID" --all -o table

  # ---------- Governance: Azure Policy (built-in "Allowed locations") ----------
  az policy assignment create -n allowed-locations --scope "$RG_ID" \
    --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
    --params '{"listOfAllowedLocations":{"value":["eastus","westeurope"]}}' -o none
fi

echo "Done: RG=$RG STG=$STG KV=$KV"
