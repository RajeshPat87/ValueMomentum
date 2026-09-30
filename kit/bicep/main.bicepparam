using 'main.bicep'

param rgName = 'kml_rg_main-abddc2859f2f4f15'
param location = 'eastus'
param deployVm = true
param deployAks = false
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY', '')
param dbPassword = readEnvironmentVariable('DB_PASSWORD', '')
