param(
  [string]$SubscriptionId,
  [string]$VaultName,
  [string]$VaultRG
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($VaultName) -or [string]::IsNullOrWhiteSpace($VaultRG)) {
  throw "SubscriptionId, VaultName, and VaultRG are required."
}

Write-Host "Creating backup policies for vault: $VaultName" -ForegroundColor Cyan
Write-Host ""

# Define policies to create
$policies = @(
  @{
    name = "daily-14d"
    retention = 14
    description = "Daily backup with 14 days retention (Non-Prod)"
  },
  @{
    name = "daily-35d"
    retention = 35
    description = "Daily backup with 35 days retention (Prod)"
  }
)

# Check if vault exists
Write-Host "Checking vault: $VaultName"
$vault = az backup vault list `
  --subscription $SubscriptionId `
  --resource-group $VaultRG `
  --output json 2>$null | ConvertFrom-Json | Where-Object { $_.name -eq $VaultName }

if (-not $vault) {
  throw "Vault not found: $VaultName in resource group $VaultRG"
}

Write-Host "✓ Vault found" -ForegroundColor Green
Write-Host ""

# List existing policies
Write-Host "Current policies in vault:" -ForegroundColor Cyan
$existingPolicies = az backup policy list `
  --vault-name $VaultName `
  --resource-group $VaultRG `
  --output json 2>$null | ConvertFrom-Json

foreach ($policy in $existingPolicies) {
  Write-Host "  - $($policy.name)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Note: Backup policies must be created manually in Azure Portal or via Azure PowerShell" -ForegroundColor Cyan
Write-Host ""
Write-Host "To create policies using Azure PowerShell, run:" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Connect-AzAccount" -ForegroundColor Gray
Write-Host "  Select-AzSubscription -SubscriptionId '$SubscriptionId'" -ForegroundColor Gray
Write-Host "  `$vault = Get-AzRecoveryServicesVault -Name '$VaultName' -ResourceGroupName '$VaultRG'" -ForegroundColor Gray
Write-Host "  Set-AzRecoveryServicesVaultContext -Vault `$vault" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Create daily-14d policy" -ForegroundColor Gray
Write-Host "  `$schedule = New-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupFrequency Daily -BackupTime 02:00" -ForegroundColor Gray
Write-Host "  `$retention = New-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM -RetentionDurationType Days -RetentionCount 14" -ForegroundColor Gray
Write-Host "  New-AzRecoveryServicesBackupProtectionPolicy -Name 'daily-14d' -WorkloadType AzureVM -RetentionPolicy `$retention -SchedulePolicy `$schedule" -ForegroundColor Gray
Write-Host ""
Write-Host "  # Create daily-35d policy" -ForegroundColor Gray
Write-Host "  `$schedule = New-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupFrequency Daily -BackupTime 02:00" -ForegroundColor Gray
Write-Host "  `$retention = New-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM -RetentionDurationType Days -RetentionCount 35" -ForegroundColor Gray
Write-Host "  New-AzRecoveryServicesBackupProtectionPolicy -Name 'daily-35d' -WorkloadType AzureVM -RetentionPolicy `$retention -SchedulePolicy `$schedule" -ForegroundColor Gray
