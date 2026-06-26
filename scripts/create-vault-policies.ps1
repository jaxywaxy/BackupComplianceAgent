param(
  [string]$SubscriptionId,
  [string]$VaultName,
  [string]$VaultRG
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($VaultName) -or [string]::IsNullOrWhiteSpace($VaultRG)) {
  throw "SubscriptionId, VaultName, and VaultRG are required."
}

Write-Host "Creating backup policies for vault: $VaultName" -ForegroundColor Cyan

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

# Get the module context
if (-not (Get-Module -Name Az.RecoveryServices -ListAvailable)) {
  Write-Host "Installing Az.RecoveryServices module..." -ForegroundColor Yellow
  Install-Module -Name Az.RecoveryServices -Force -AllowClobber -Scope CurrentUser
}

Import-Module Az.RecoveryServices -Force

# Set context to subscription
Select-AzSubscription -SubscriptionId $SubscriptionId | Out-Null

# Get vault
Write-Host "Loading vault: $VaultName" -ForegroundColor Cyan
$vault = Get-AzRecoveryServicesVault -Name $VaultName -ResourceGroupName $VaultRG

if (-not $vault) {
  throw "Vault not found: $VaultName in resource group $VaultRG"
}

Set-AzRecoveryServicesVaultContext -Vault $vault

# Create policies
foreach ($policyDef in $policies) {
  $policyName = $policyDef.name
  $retentionDays = $policyDef.retention

  Write-Host ""
  Write-Host "Policy: $policyName ($retentionDays days retention)" -ForegroundColor Yellow

  # Check if policy exists
  try {
    $existingPolicy = Get-AzRecoveryServicesBackupProtectionPolicy -Name $policyName -ErrorAction SilentlyContinue
    if ($existingPolicy) {
      Write-Host "  ✓ Policy already exists" -ForegroundColor Green
      continue
    }
  } catch {
    # Policy doesn't exist, continue to create it
  }

  try {
    # Get default schedule policy
    $schedulePolicy = New-AzRecoveryServicesBackupSchedulePolicyObject -WorkloadType AzureVM -BackupManagementType AzureVM -BackupFrequency Daily -BackupTime 02:00

    # Get default retention policy
    $retentionPolicy = New-AzRecoveryServicesBackupRetentionPolicyObject -WorkloadType AzureVM `
      -BackupManagementType AzureVM `
      -RetentionDurationType Days `
      -RetentionCount $retentionDays

    # Create the policy
    New-AzRecoveryServicesBackupProtectionPolicy `
      -Name $policyName `
      -WorkloadType AzureVM `
      -BackupManagementType AzureVM `
      -RetentionPolicy $retentionPolicy `
      -SchedulePolicy $schedulePolicy `
      -VaultId $vault.ID | Out-Null

    Write-Host "  ✓ Policy created successfully" -ForegroundColor Green
  } catch {
    Write-Host "  ✗ Failed to create policy: $_" -ForegroundColor Red
    throw
  }
}

Write-Host ""
Write-Host "✓ All policies created successfully" -ForegroundColor Green
Write-Host ""
Write-Host "Use these policy names in your backup-rules.yaml:" -ForegroundColor Cyan
foreach ($policy in $policies) {
  Write-Host "  - $($policy.name)" -ForegroundColor Cyan
}
