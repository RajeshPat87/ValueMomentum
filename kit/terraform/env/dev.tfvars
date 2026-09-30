# dev = KodeKloud-style playground: RG-scoped SPN, restrictive Key Vault policy (same flags as main-rg.bicepparam)
# No secrets here. RG, SSH key and DB password come from env (deploy.sh maps RG/SSH_PUBLIC_KEY/DB_PASSWORD to TF_VAR_*).
env                 = "dev"
location            = "eastus"
vm_size             = "Standard_B1s"
deploy_vm           = true
deploy_aks          = false
deploy_rbac         = false
kv_purge_protection = false
kv_soft_delete_days = 7
