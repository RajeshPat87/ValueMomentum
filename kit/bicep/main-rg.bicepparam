using 'main-rg.bicep'

param deployVm = true
param deployAks = false
param deployRbac = false
param kvPurgeProtection = false // playground policy: no purge protection
param kvSoftDeleteDays = 7      // playground policy: 7-day soft delete
param sshPublicKey = readEnvironmentVariable('SSH_PUBLIC_KEY')
param dbPassword = readEnvironmentVariable('DB_PASSWORD')
