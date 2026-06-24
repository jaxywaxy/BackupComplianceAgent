param(
  [string]$VaultName,
  [string]$VaultRG,
  [string]$VmName,
  [string]$VmRG
)

Write-Host "Enabling backup for $VmName..."

$policy = az backup policy list `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  | ConvertFrom-Json | Select-Object -First 1

az backup protection enable-for-vm `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  --vm $VmName `
  --vm-resource-group $VmRG `
  --policy-name $policy.name

Write-Host "Backup enabled"
``
