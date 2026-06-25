param(
  [string]$VaultName,
  [string]$VaultRG,
  [string]$VmName,
  [string]$VmRG,
  [string]$PolicyName
)

if ([string]::IsNullOrWhiteSpace($VaultName) -or [string]::IsNullOrWhiteSpace($VaultRG) -or [string]::IsNullOrWhiteSpace($VmName) -or [string]::IsNullOrWhiteSpace($VmRG)) {
  throw "VaultName, VaultRG, VmName, and VmRG are required."
}

Write-Host "Enabling backup for $VmName..."

$policyNameToUse = $PolicyName
if ([string]::IsNullOrWhiteSpace($policyNameToUse)) {
  $policy = az backup policy list `
    --vault-name $VaultName `
    --resource-group $VaultRG `
    | ConvertFrom-Json | Select-Object -First 1
  if (-not $policy) {
    throw "No backup policy found in vault $VaultName."
  }
  $policyNameToUse = $policy.name
}

if ([string]::IsNullOrWhiteSpace($policyNameToUse)) {
  throw "Backup policy name could not be resolved for vault $VaultName."
}

az backup protection enable-for-vm `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  --vm $VmName `
  --vm-resource-group $VmRG `
  --policy-name $policyNameToUse

Write-Host "Backup enabled with policy $policyNameToUse"

