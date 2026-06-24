param location string = 'australiaeast'
param vaultName string

resource vault 'Microsoft.RecoveryServices/vaults@2023-02-01' = {
  name: vaultName
  location: location
  properties: {}
}

output vaultId string = vault.id
