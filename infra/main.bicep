// Backup Compliance Agent Infrastructure
// Azure Bicep deployment for Recovery Services vaults and supporting resources

param location string = resourceGroup().location
param environment string = 'dev'
param vaultName string = 'backup-vault-${environment}'
param redundancy string = 'GeoRedundant'

// Recovery Services Vault
resource vault 'Microsoft.RecoveryServices/vaults@2023-04-01' = {
  name: vaultName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    redundancySettings: {
      crossRegionRestore: redundancy == 'GeoRedundant' ? 'Enabled' : 'Disabled'
      standardTierStorageRedundancy: redundancy
    }
  }
}

// Vault backup configuration
resource vaultBackupConfig 'Microsoft.RecoveryServices/vaults/backupconfig@2023-04-01' = {
  parent: vault
  name: 'vaultconfig'
  properties: {
    enhancedSecurityState: 'Enabled'
    softDeleteFeatureState: 'Enabled'
    resourceGuardOperationRequests: []
  }
}

output vaultId string = vault.id
output vaultName string = vault.name
output vaultLocation string = vault.location
