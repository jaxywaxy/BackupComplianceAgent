param(
  [string]$SubscriptionId,
  [string]$VaultName,
  [string]$VaultRG
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($VaultName) -or [string]::IsNullOrWhiteSpace($VaultRG)) {
  throw "SubscriptionId, VaultName, and VaultRG are required."
}

Write-Host "=== Vault Policies ===" -ForegroundColor Cyan
Write-Host "Vault: $VaultName"
Write-Host "Resource Group: $VaultRG"
Write-Host ""

$policies = az backup policy list `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  --output json | ConvertFrom-Json

if (-not $policies) {
  Write-Host "✗ No policies found in vault" -ForegroundColor Red
  exit 1
}

Write-Host "Available policies:" -ForegroundColor Green
foreach ($policy in $policies) {
  Write-Host "  - $($policy.name)" -ForegroundColor Green
}

Write-Host ""
Write-Host "Use these policy names in your backup-rules.yaml:" -ForegroundColor Yellow
foreach ($policy in $policies) {
  Write-Host "    $($policy.name)" -ForegroundColor Yellow
}
