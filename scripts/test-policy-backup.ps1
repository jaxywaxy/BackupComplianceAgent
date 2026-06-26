param(
  [string]$SubscriptionId,
  [string]$VaultName,
  [string]$VaultRG,
  [string]$VmName,
  [string]$VmRG,
  [string]$PolicyName = "DefaultPolicy"
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($VaultName) -or [string]::IsNullOrWhiteSpace($VaultRG)) {
  throw "SubscriptionId, VaultName, and VaultRG are required."
}

Write-Host "=== Testing Backup Policy ===" -ForegroundColor Cyan
Write-Host ""

# List all policies and their details
Write-Host "Policies in vault: $VaultName" -ForegroundColor Yellow
$policies = az backup policy list `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  --output json | ConvertFrom-Json

foreach ($policy in $policies) {
  Write-Host ""
  Write-Host "Policy: $($policy.name)" -ForegroundColor Cyan
  Write-Host "  ID: $($policy.id)" -ForegroundColor Gray
  Write-Host "  Type: $($policy.type)" -ForegroundColor Gray

  # Try to get details
  $details = az backup policy show `
    --vault-name $VaultName `
    --resource-group $VaultRG `
    --name $policy.name `
    --output json 2>$null | ConvertFrom-Json

  if ($details) {
    Write-Host "  Properties: $($details.properties | ConvertTo-Json -Depth 2)" -ForegroundColor Gray
  }
}

Write-Host ""
Write-Host "=== Testing Backup Enable ===" -ForegroundColor Cyan

if ($VmName -and $VmRG) {
  Write-Host ""
  Write-Host "Testing backup enable for: $VmName (in $VmRG)" -ForegroundColor Yellow

  # Get VM details
  $vm = az vm show --name $VmName --resource-group $VmRG --output json | ConvertFrom-Json
  Write-Host "VM ID: $($vm.id)" -ForegroundColor Gray
  Write-Host "VM Type: $($vm.type)" -ForegroundColor Gray

  if ($vm.properties.securityProfile) {
    Write-Host "Security Profile: $($vm.properties.securityProfile | ConvertTo-Json)" -ForegroundColor Gray
  }

  Write-Host ""
  Write-Host "Attempting to enable backup with policy: $PolicyName" -ForegroundColor Yellow

  $vmResourceId = $vm.id

  # Try the backup command
  $output = az backup protection enable-for-vm `
    --vault-name $VaultName `
    --resource-group $VaultRG `
    --vm $vmResourceId `
    --policy-name $PolicyName `
    2>&1

  if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ SUCCESS: Backup enabled!" -ForegroundColor Green
    Write-Host $output
  } else {
    Write-Host "✗ FAILED" -ForegroundColor Red
    Write-Host $output
  }
} else {
  Write-Host "VM name and resource group not provided, skipping backup test" -ForegroundColor Yellow
}
