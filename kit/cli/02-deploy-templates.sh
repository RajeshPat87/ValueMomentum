#!/usr/bin/env bash
# TEMPLATE deployment. Rule: file scope == command scope (group | sub | mg | tenant)
# Reference script: read it section by section. Subscription-scope lines run only with SUB_SCOPE=true.
set -euo pipefail
RG=${RG:-rg-demo}; LOC=${LOC:-eastus}
SUB_SCOPE=${SUB_SCOPE:-false}          # true only where you may deploy at subscription scope (not on KodeKloud)

# ---- Bicep ----
[ "$SUB_SCOPE" = true ] && az deployment sub create -l $LOC -f ../bicep/modules/01-rg.bicep -p rgName=$RG   # targetScope='subscription'
az deployment group create  -g $RG -f ../bicep/modules/02-storage.bicep -n storage       # default scope = RG
az deployment group what-if -g $RG -f ../bicep/modules/03-network.bicep                  # preview
: "${SSH_PUBLIC_KEY:?source ../bicep/modules/set-secrets.sh first}"
az deployment group create  -g $RG -p ../bicep/main-rg.bicepparam -n main-rg             # everything, existing RG
[ "$SUB_SCOPE" = true ] && az deployment sub create -l $LOC -f ../bicep/main.bicep -p ../bicep/main.bicepparam  # everything + RG
# Same flow, with dependency wiring done for you: ../bicep/deploy.sh <validate|what-if|create> <target>

# ---- ARM JSON (same commands, .json file) ----
[ "$SUB_SCOPE" = true ] && az deployment sub create -l $LOC -f ../arm/rg.json -p rgName=$RG
az deployment group create -g $RG -f ../arm/storage.json -p @../arm/storage.parameters.json -n storage
az deployment group create -g $RG -f ../arm/network.json --mode Incremental -n network   # Complete would delete what's not in the file
# Same flow: ../arm/deploy.sh <validate|what-if|create> <target>

# ---- Convert ----
az bicep build     -f ../bicep/main.bicep --stdout >/dev/null   # Bicep -> ARM JSON
az bicep decompile -f ../arm/network.json --force               # ARM JSON -> Bicep (best effort, writes ../arm/network.bicep)
rm -f ../arm/network.bicep

# ---- Lifecycle with deployment stacks (manages deletes) ----
az stack group create -n stack-demo -g $RG -f ../bicep/modules/02-storage.bicep \
  --action-on-unmanage deleteResources --deny-settings-mode none --yes
# --deny-settings-mode denyDelete also blocks deletes outside the stack; needs deploymentStacks/manageDenySetting/action (Owner or Azure Deployment Stack Owner)

# ---- Inspect / troubleshoot ----
az deployment group list -g $RG -o table
az deployment operation group list -g $RG -n storage --query "[?properties.provisioningState=='Failed']"
