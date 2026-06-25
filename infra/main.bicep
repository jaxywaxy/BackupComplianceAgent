param location string = 'australiaeast'
param vaultName string
param skuName string = 'Standard'
param enableSoftDelete bool = true

resource vault 'Microsoft.RecoveryServices/vaults@2023-02-01' = {
  name: vaultName
  location: location
  sku: {
    name: skuName
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

resource vaultProperties 'Microsoft.RecoveryServices/vaults/backupconfig@2023-02-01' = {
  parent: vault
  name: 'vaultconfig'
  properties: {
    enhancedSecurityState: enableSoftDelete ? 'Enabled' : 'Disabled'
    softDeleteFeatureState: enableSoftDelete ? 'Enabled' : 'Disabled'
  }
}

output vaultId string = vault.id
output vaultName string = vault.name
output vaultLocation string = vault.location
