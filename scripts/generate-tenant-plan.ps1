param(
  [string[]]$SubscriptionIds,
  [switch]$AllSubscriptions,
  [string]$OutputDir = './output/plans'
)

Write-Host "=== Tenant-Level Backup Remediation Plan ===" -ForegroundColor Cyan
Write-Host ""

# Determine subscriptions to scan
$subscriptionsToScan = @()

if ($AllSubscriptions -or -not $SubscriptionIds) {
  Write-Host "Discovering all subscriptions..." -ForegroundColor Yellow
  $allSubs = az account list --output json | ConvertFrom-Json
  $subscriptionsToScan = $allSubs | ForEach-Object { $_.id }
  Write-Host "Found $($subscriptionsToScan.Count) subscriptions" -ForegroundColor Green
} else {
  $subscriptionsToScan = $SubscriptionIds
  Write-Host "Scanning $($subscriptionsToScan.Count) specified subscription(s)" -ForegroundColor Green
}

if ($subscriptionsToScan.Count -eq 0) {
  Write-Host "✗ No subscriptions to scan" -ForegroundColor Red
  exit 1
}

Write-Host ""

# Initialize tenant-level results
$tenantPlan = [PSCustomObject]@{
  generatedAt = Get-Date -Format 'u'
  tenantId = (az account show --query tenantId -o tsv)
  subscriptionCount = $subscriptionsToScan.Count
  subscriptions = @()
  summary = @{
    totalVMs = 0
    compliantVMs = 0
    nonCompliantVMs = 0
    vaultDeploymentsNeeded = 0
    notificationsCount = 0
  }
}

# Scan each subscription
$subscriptionResults = @()

foreach ($subId in $subscriptionsToScan) {
  Write-Host "Scanning subscription: $subId" -ForegroundColor Cyan
  Write-Host "================================================" -ForegroundColor Cyan

  try {
    # Get subscription details
    $subInfo = az account show --subscription $subId --query "{id:id, name:name}" -o json | ConvertFrom-Json

    Write-Host "Subscription Name: $($subInfo.name)" -ForegroundColor Yellow
    Write-Host ""

    # Generate plan for this subscription
    $planOutput = & "./scripts/generate-plan.ps1" -SubscriptionId $subId 2>&1 | Out-String

    # Read the generated JSON (save to subscription-specific file)
    $subPlanFile = "$OutputDir/remediation.json"
    $subPlanFileBackup = "$OutputDir/remediation-$($subId).json"

    if (Test-Path $subPlanFile) {
      $subPlan = Get-Content $subPlanFile | ConvertFrom-Json

      # Also save a subscription-specific copy for reference
      Copy-Item $subPlanFile $subPlanFileBackup -Force

      # Count VMs
      $vaultCount = if ($subPlan.vaultDeployments) { $subPlan.vaultDeployments.Count } else { 0 }
      $planCount = if ($subPlan.plan) { $subPlan.plan.Count } else { 0 }
      $notifCount = if ($subPlan.notifications) { $subPlan.notifications.Count } else { 0 }

      # Add to tenant summary
      $tenantPlan.summary.vaultDeploymentsNeeded += $vaultCount
      $tenantPlan.summary.nonCompliantVMs += $planCount
      $tenantPlan.summary.notificationsCount += $notifCount

      # Store subscription result
      $subResult = [PSCustomObject]@{
        subscriptionId = $subId
        subscriptionName = $subInfo.name
        vaultDeploymentsCount = $vaultCount
        vmsNeedingBackupCount = $planCount
        notificationsCount = $notifCount
        plan = $subPlan.plan
        vaultDeploymentDetails = $subPlan.vaultDeployments
        notificationDetails = $subPlan.notifications
      }

      $tenantPlan.subscriptions += $subResult
      $subscriptionResults += $subResult

      Write-Host "✓ Vaults needed: $vaultCount | VMs needing backup: $planCount | Notifications: $notifCount" -ForegroundColor Green
    } else {
      Write-Host "⚠️  No plan generated for this subscription" -ForegroundColor Yellow
    }

  } catch {
    Write-Host "✗ Error scanning subscription: $_" -ForegroundColor Red
  }

  Write-Host ""
}

# Save tenant plan
$tenantPlanFile = "$OutputDir/tenant-plan.json"
$tenantPlan | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 $tenantPlanFile
Write-Host "Tenant plan written to: $tenantPlanFile" -ForegroundColor Green

# Generate tenant summary markdown
$markdownFile = "$OutputDir/tenant-summary.md"
$md = @()
$md += "# Tenant-Level Backup Compliance Report"
$md += ""
$md += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$md += ""
$md += "## Executive Summary"
$md += ""
$md += "| Metric | Count |"
$md += "|--------|-------|"
$md += "| Subscriptions Scanned | $($tenantPlan.subscriptionCount) |"
$md += "| Total Non-Compliant VMs | $($tenantPlan.summary.nonCompliantVMs) |"
$md += "| Vault Deployments Needed | $($tenantPlan.summary.vaultDeploymentsNeeded) |"
$md += "| Notifications | $($tenantPlan.summary.notificationsCount) |"
$md += ""

$md += "## Subscription Details"
$md += ""

foreach ($result in $subscriptionResults) {
  $md += "### $($result.subscriptionName)"
  $md += ""
  $md += "**ID:** $($result.subscriptionId)"
  $md += ""
  $md += "| Metric | Count |"
  $md += "|--------|-------|"
  $md += "| VMs Needing Backup | $($result.vmsNeedingBackup) |"
  $md += "| Vault Deployments | $($result.vaultDeployments) |"
  $md += "| Notifications | $($result.notifications) |"
  $md += ""

  if ($result.plan -and $result.plan.Count -gt 0) {
    $md += "**VMs to Protect:**"
    $md += ""
    foreach ($vm in $result.plan) {
      $md += "- **$($vm.vmName)** (Owner: $($vm.owner ?? 'N/A'))"
      $md += "  - Environment: $($vm.environment)"
      $md += "  - Vault: $($vm.vaultName)"
      $md += "  - Policy: $($vm.policyName)"
      $md += ""
    }
  }

  if ($result.notifications -and $result.notifications.Count -gt 0) {
    $md += "**Notifications:**"
    $md += ""
    foreach ($notif in $result.notifications) {
      $md += "- $($notif.level): $($notif.message)"
      if ($notif.vmName) { $md += "  - VM: $($notif.vmName)" }
      $md += ""
    }
  }

  $md += "---"
  $md += ""
}

$md += "## Next Steps"
$md += ""
$md += "1. Review the detailed plan in tenant-plan.json"
$md += ""
$md += "2. For each subscription, create a remediation PR"
$md += ""
$md += "3. Approve and merge PRs to apply remediation"
$md += ""
$md += "4. Monitor backup jobs in Azure Portal"
$md += ""

$md -join "`n" | Out-File -Encoding utf8 $markdownFile
Write-Host "Tenant summary written to: $markdownFile" -ForegroundColor Green

Write-Host ""
Write-Host "=== Tenant Plan Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Subscriptions: $($tenantPlan.subscriptionCount)" -ForegroundColor Yellow
Write-Host "  Non-Compliant VMs: $($tenantPlan.summary.nonCompliantVMs)" -ForegroundColor Yellow
Write-Host "  Vault Deployments Needed: $($tenantPlan.summary.vaultDeploymentsNeeded)" -ForegroundColor Yellow
Write-Host "  Total Notifications: $($tenantPlan.summary.notificationsCount)" -ForegroundColor Yellow
Write-Host ""
