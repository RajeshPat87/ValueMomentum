#!/usr/bin/env bash
# bootstrap-state.sh — create the Terraform state storage once (idempotent; safe to re-run)
#   ./bootstrap-state.sh              create account + container in $TFSTATE_RG (default: $RG)
#   ./bootstrap-state.sh --name-only  print the account name deploy.sh will use, create nothing
#
# Env: RG or TFSTATE_RG (where the account lives), TFSTATE_ACCOUNT (default: derived from subscription + RG),
#      TFSTATE_CONTAINER (default tfstate)
# Needs only RG Contributor: the backend uses the account key (listKeys), not a data-plane role.
set -euo pipefail

TFSTATE_RG=${TFSTATE_RG:-${RG:-}}
: "${TFSTATE_RG:?export RG (or TFSTATE_RG) first}"
TFSTATE_CONTAINER=${TFSTATE_CONTAINER:-tfstate}
if [ -z "${TFSTATE_ACCOUNT:-}" ]; then
  sub=$(az account show --query id -o tsv)
  TFSTATE_ACCOUNT="sttf$(printf '%s/%s' "$sub" "$TFSTATE_RG" | sha256sum | cut -c1-12)"   # 16 chars, stable per RG
fi

if [ "${1:-}" = --name-only ]; then echo "$TFSTATE_ACCOUNT"; exit 0; fi

echo "==> state account $TFSTATE_ACCOUNT in $TFSTATE_RG"
az storage account create -g "$TFSTATE_RG" -n "$TFSTATE_ACCOUNT" \
  --sku Standard_LRS --kind StorageV2 --min-tls-version TLS1_2 \
  --https-only true --allow-blob-public-access false -o none
az storage container create --account-name "$TFSTATE_ACCOUNT" -n "$TFSTATE_CONTAINER" --auth-mode key -o none
echo "ready: export TFSTATE_RG=$TFSTATE_RG TFSTATE_ACCOUNT=$TFSTATE_ACCOUNT"
