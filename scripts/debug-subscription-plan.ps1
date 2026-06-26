param(
  [string]$SubscriptionId,
  [string]$PlanFile = './output/plans/remediation.json'
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  throw "SubscriptionId is required."
}

Write-Host "=== Debugging Subscription Plan ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId" -ForegroundColor Yellow
Write-Host ""

# Step 1: List all VMs in subscription
Write-Host "Step 1: Scanning VMs in subscription..." -ForegroundColor Yellow
$vms = az vm list --subscription $SubscriptionId --output json | ConvertFrom-Json

if (-not $vms) {
  Write-Host "✗ No VMs found in subscription" -ForegroundColor Red
  exit 1
}

Write-Host "Found $($vms.Count) VMs:" -ForegroundColor Green
foreach ($vm in $vms) {
  Write-Host "  - $($vm.name) (Region: $($vm.location))" -ForegroundColor Gray
}
Write-Host ""

# Step 2: Check each VM's tags and backup status
Write-Host "Step 2: Checking each VM..." -ForegroundColor Yellow
Write-Host ""

$vaultCount = 0
$vms | ForEach-Object {
  $vmName = $_.name
  $vmId = $_.id
  $vmRg = $_.resourceGroup
  $vmLocation = $_.location

  Write-Host "VM: $vmName" -ForegroundColor Cyan
  Write-Host "  Resource Group: $vmRg" -ForegroundColor Gray
  Write-Host "  Location: $vmLocation" -ForegroundColor Gray
  Write-Host "  ID: $vmId" -ForegroundColor Gray

  # Check tags
  if ($_.tags) {
    Write-Host "  Tags:" -ForegroundColor Yellow
    $_.tags.PSObject.Properties | ForEach-Object {
      Write-Host "    $($_.Name): $($_.Value)" -ForegroundColor Gray
    }
  } else {
    Write-Host "  Tags: ✗ None" -ForegroundColor Red
  }

  # Check backup status
  Write-Host "  Backup Status:" -ForegroundColor Yellow
  $backupStatus = az backup item list `
    --vault-name "rsv-backup-aus-001" `
    --resource-group "rg-backup-shared" `
    --output json 2>$null | ConvertFrom-Json | Where-Object {
      $_.properties.sourceResourceId -eq $vmId
    }

  if ($backupStatus) {
    Write-Host "    ✓ Already protected" -ForegroundColor Green
  } else {
    Write-Host "    ✗ Not protected" -ForegroundColor Red
  }

  Write-Host ""
}

Write-Host "Step 3: Checking generated plan..." -ForegroundColor Yellow

if (Test-Path $PlanFile) {
  $plan = Get-Content $PlanFile | ConvertFrom-Json

  $vaultDeployments = if ($plan.vaultDeployments) { $plan.vaultDeployments.Count } else { 0 }
  $planItems = if ($plan.plan) { $plan.plan.Count } else { 0 }
  $notifications = if ($plan.notifications) { $plan.notifications.Count } else { 0 }

  Write-Host "Plan Summary:" -ForegroundColor Green
  Write-Host "  Vault Deployments: $vaultDeployments" -ForegroundColor Yellow
  Write-Host "  VMs Needing Backup: $planItems" -ForegroundColor Yellow
  Write-Host "  Notifications: $notifications" -ForegroundColor Yellow
  Write-Host ""

  if ($planItems -gt 0) {
    Write-Host "VMs in Plan:" -ForegroundColor Yellow
    foreach ($item in $plan.plan) {
      Write-Host "  - $($item.vmName)" -ForegroundColor Green
      Write-Host "    Owner: $($item.owner)" -ForegroundColor Gray
      Write-Host "    Environment: $($item.environment)" -ForegroundColor Gray
      Write-Host "    Vault: $($item.vaultName)" -ForegroundColor Gray
      Write-Host "    Policy: $($item.policyName)" -ForegroundColor Gray
    }
  }

  if ($notifications -gt 0) {
    Write-Host ""
    Write-Host "Notifications (Issues):" -ForegroundColor Red
    foreach ($notif in $plan.notifications) {
      Write-Host "  [$($notif.level)] $($notif.message)" -ForegroundColor Red
      if ($notif.vmName) {
        Write-Host "    VM: $($notif.vmName)" -ForegroundColor Gray
      }
      if ($notif.resourceGroup) {
        Write-Host "    RG: $($notif.resourceGroup)" -ForegroundColor Gray
      }
    }
  }
} else {
  Write-Host "⚠️  Plan file not found: $PlanFile" -ForegroundColor Yellow
  Write-Host "Run: pwsh ./scripts/generate-plan.ps1 -SubscriptionId '$SubscriptionId'" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Debug Complete ===" -ForegroundColor Green
