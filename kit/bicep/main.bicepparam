using 'main.bicep'

param rgName = 'kml_rg_main-42c127d8a76847bd'
param location = 'eastus'
param deployVm = true
param deployAks = false
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')
param dbPassword = readEnvironmentVariable('DB_PASSWORD', '')
