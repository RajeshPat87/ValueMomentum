#!/usr/bin/env bash
# TEMPLATE deployment. Rule: file scope == command scope (group | sub | mg | tenant)
set -euo pipefail
RG=rg-demo; LOC=eastus

# ---- Bicep ----
az deployment sub create   -l $LOC -f ../bicep/modules/01-rg.bicep -p rgName=$RG       # targetScope='subscription'
az deployment group create -g $RG  -f ../bicep/modules/02-storage.bicep                # default scope = RG
az deployment group what-if -g $RG -f ../bicep/modules/03-network.bicep                # preview
export SSH_PUBLIC_KEY="$(cat ~/.ssh/id_rsa.pub)"
az deployment sub create   -l $LOC -f ../bicep/main.bicep -p ../bicep/main.bicepparam  # everything

# ---- ARM JSON (same commands, .json file) ----
az deployment sub create   -l $LOC -f ../arm/rg.json -p rgName=$RG
az deployment group create -g $RG  -f ../arm/storage.json -p @../arm/storage.parameters.json
az deployment group create -g $RG  -f ../arm/network.json --mode Incremental

# ---- Convert ----
az bicep build     -f ../bicep/main.bicep            # Bicep -> ARM JSON
az bicep decompile -f ../arm/network.json            # ARM JSON -> Bicep (best effort)

# ---- Lifecycle with deployment stacks (manages deletes) ----
az stack group create -n stack-demo -g $RG -f ../bicep/modules/02-storage.bicep \
  --action-on-unmanage deleteResources --deny-settings-mode denyDelete

# ---- Inspect / troubleshoot ----
az deployment group list -g $RG -o table
az deployment operation group list -g $RG -n storage --query "[?properties.provisioningState=='Failed']"
