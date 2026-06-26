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
    --output json `
    | ConvertFrom-Json | Select-Object -First 1
  if (-not $policy) {
    throw "No backup policy found in vault $VaultName."
  }
  $policyNameToUse = $policy.name
}

if ([string]::IsNullOrWhiteSpace($policyNameToUse)) {
  throw "Backup policy name could not be resolved for vault $VaultName."
}

Write-Host "Enabling backup with policy: $policyNameToUse"

# Build the full resource ID for the VM
$vmResourceId = "/subscriptions/$((az account show --query id -o tsv))/resourceGroups/$VmRG/providers/Microsoft.Compute/virtualMachines/$VmName"
Write-Host "VM Resource ID: $vmResourceId"

# Enable backup using the VM resource ID
az backup protection enable-for-vm `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  --vm $vmResourceId `
  --policy-name $policyNameToUse

if ($LASTEXITCODE -ne 0) {
  throw "Failed to enable backup for VM: $VmName"
}

Write-Host "✓ Backup enabled with policy $policyNameToUse" -ForegroundColor Green

