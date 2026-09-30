#!/usr/bin/env bash
# DIRECT creation (no template). Pattern: az <noun> [<sub>] <verb> -g -n -l --flags ; capture: --query id -o tsv
set -euo pipefail

SUB_ID="<subscription-id>"
RG=rg-demo
LOC=eastus
SFX=$RANDOM
az account set --subscription "$SUB_ID"

# ---------- Resource group ----------
az group create -n $RG -l $LOC --tags env=dev

# ---------- Storage ----------
STG="stdemo$SFX"
az storage account create -g $RG -n $STG -l $LOC \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 --https-only true --allow-blob-public-access false
az storage container create --account-name $STG -n data --auth-mode login
STG_ID=$(az storage account show -g $RG -n $STG --query id -o tsv)

# ---------- Networking ----------
az network nsg create -g $RG -n nsg-web
az network nsg rule create -g $RG --nsg-name nsg-web -n Allow-HTTPS-In \
  --priority 100 --direction Inbound --access Allow --protocol Tcp \
  --source-address-prefixes '*' --destination-port-ranges 443

az network vnet create -g $RG -n vnet-demo --address-prefixes 10.0.0.0/16 \
  --subnet-name snet-web --subnet-prefixes 10.0.1.0/24 --network-security-group nsg-web
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-pe  --address-prefixes 10.0.2.0/24
az network vnet subnet create -g $RG --vnet-name vnet-demo -n snet-aks --address-prefixes 10.0.4.0/22

VNET_ID=$(az network vnet show -g $RG -n vnet-demo --query id -o tsv)
WEB_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name vnet-demo -n snet-web --query id -o tsv)
AKS_SUBNET_ID=$(az network vnet subnet show -g $RG --vnet-name vnet-demo -n snet-aks --query id -o tsv)

# Peering (needs both directions)
# az network vnet peering create -g $RG -n demo-to-hub --vnet-name vnet-demo --remote-vnet "$HUB_VNET_ID" --allow-vnet-access --allow-forwarded-traffic

# ---------- Compute: VM ----------
az vm create -g $RG -n vm01 --image Ubuntu2404 --size Standard_B2s \
  --admin-username azureuser --generate-ssh-keys \
  --subnet "$WEB_SUBNET_ID" --public-ip-address "" --nsg "" \
  --assign-identity
VM_PRINCIPAL=$(az vm show -g $RG -n vm01 --query identity.principalId -o tsv)

# ---------- Compute: AKS ----------
az aks create -g $RG -n aks-demo --node-count 2 --node-vm-size Standard_D4s_v5 \
  --network-plugin azure --network-policy azure --vnet-subnet-id "$AKS_SUBNET_ID" \
  --service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10 \
  --enable-managed-identity --enable-aad --enable-azure-rbac \
  --enable-oidc-issuer --enable-workload-identity --generate-ssh-keys
az aks get-credentials -g $RG -n aks-demo

# ---------- Security: identity + Key Vault + private endpoint ----------
az identity create -g $RG -n id-app
UAMI_PID=$(az identity show -g $RG -n id-app --query principalId -o tsv)

KV="kv-demo-$SFX"
az keyvault create -g $RG -n $KV -l $LOC \
  --enable-rbac-authorization true --enable-purge-protection true --retention-days 90
KV_ID=$(az keyvault show -n $KV --query id -o tsv)

ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$ME" --assignee-principal-type User \
  --role "Key Vault Secrets Officer" --scope "$KV_ID"
az keyvault secret set --vault-name $KV -n db-password --value "$(openssl rand -base64 24)"

# lock down AFTER seeding secret (data plane needs network access)
az keyvault update -n $KV --public-network-access Disabled --default-action Deny --bypass AzureServices

az network private-endpoint create -g $RG -n pe-kv --vnet-name vnet-demo --subnet snet-pe \
  --private-connection-resource-id "$KV_ID" --group-id vault --connection-name psc-kv
az network private-dns zone create -g $RG -n privatelink.vaultcore.azure.net
az network private-dns link vnet create -g $RG -n link-vnet \
  --zone-name privatelink.vaultcore.azure.net --virtual-network "$VNET_ID" --registration-enabled false
az network private-endpoint dns-zone-group create -g $RG --endpoint-name pe-kv -n default \
  --private-dns-zone privatelink.vaultcore.azure.net --zone-name kv

# ---------- RBAC ----------
az role assignment create --assignee-object-id "$UAMI_PID" --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" --scope "$KV_ID"
az role assignment create --assignee-object-id "$UAMI_PID" --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$STG_ID"
az role assignment create --assignee-object-id "$VM_PRINCIPAL" --assignee-principal-type ServicePrincipal \
  --role Reader --scope "/subscriptions/$SUB_ID/resourceGroups/$RG"

cat > /tmp/vm-operator.json <<JSON
{
  "Name": "VM Operator ($RG)",
  "Description": "Read, start and restart VMs",
  "Actions": [
    "Microsoft.Compute/virtualMachines/read",
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/restart/action"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/$SUB_ID/resourceGroups/$RG"]
}
JSON
az role definition create --role-definition @/tmp/vm-operator.json
az role assignment list --assignee "$UAMI_PID" --all -o table

# ---------- Governance: Azure Policy (built-in "Allowed locations") ----------
az policy assignment create -n allowed-locations \
  --scope "/subscriptions/$SUB_ID/resourceGroups/$RG" \
  --policy e56962a6-4747-49cd-b67b-bf8b01975c4c \
  --params '{"listOfAllowedLocations":{"value":["eastus","westeurope"]}}'
