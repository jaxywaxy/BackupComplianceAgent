param(
  [string]$TenantPlanFile = './output/plans/tenant-plan.json',
  [switch]$DryRun,
  [switch]$AutoApply
)

Write-Host "=== Multi-Subscription Remediation ===" -ForegroundColor Cyan
Write-Host ""

# Load tenant plan
if (-not (Test-Path $TenantPlanFile)) {
  throw "Tenant plan file not found: $TenantPlanFile"
}

$tenantPlan = Get-Content $TenantPlanFile | ConvertFrom-Json

Write-Host "Tenant ID: $($tenantPlan.tenantId)" -ForegroundColor Yellow
Write-Host "Subscriptions to process: $($tenantPlan.subscriptionCount)" -ForegroundColor Yellow
Write-Host ""

$remediationResults = @{
  successful = @()
  failed = @()
  skipped = @()
}

# Process each subscription
foreach ($subResult in $tenantPlan.subscriptions) {
  $subId = $subResult.subscriptionId
  $subName = $subResult.subscriptionName
  $vmCount = $subResult.vmsNeedingBackupCount

  Write-Host "Processing: $subName" -ForegroundColor Cyan
  Write-Host "  VMs needing backup: $vmCount" -ForegroundColor Yellow

  if ($vmCount -eq 0) {
    Write-Host "  ✓ No action needed (all compliant)" -ForegroundColor Green
    $remediationResults.skipped += @{
      subscription = $subName
      reason = "No non-compliant VMs"
    }
    Write-Host ""
    continue
  }

  # Generate subscription-level remediation plan
  Write-Host "  Generating subscription remediation plan..." -ForegroundColor Yellow

  try {
    # Generate plan for this subscription
    & "./scripts/generate-plan.ps1" -SubscriptionId $subId 2>&1 | Out-Null

    # Read the generated plan
    $planFile = "./output/plans/remediation.json"
    if (-not (Test-Path $planFile)) {
      Write-Host "  ✗ Failed to generate plan" -ForegroundColor Red
      $remediationResults.failed += @{
        subscription = $subName
        reason = "Plan generation failed"
      }
      Write-Host ""
      continue
    }

    $plan = Get-Content $planFile | ConvertFrom-Json

    $vaultCount = if ($plan.vaultDeployments) { $plan.vaultDeployments.Count } else { 0 }
    $planItemCount = if ($plan.plan) { $plan.plan.Count } else { 0 }

    Write-Host "  Plan: $vaultCount vaults, $planItemCount VMs" -ForegroundColor Gray

    if ($DryRun) {
      Write-Host "  [DRY RUN] Would apply remediation" -ForegroundColor Yellow
      $remediationResults.successful += @{
        subscription = $subName
        vaults = $vaultCount
        vms = $planItemCount
        status = "dry-run"
      }
      Write-Host ""
      continue
    }

    # Deploy vaults if needed
    if ($vaultCount -gt 0) {
      Write-Host "  Deploying $vaultCount vault(s)..." -ForegroundColor Yellow

      foreach ($deployment in $plan.vaultDeployments) {
        Write-Host "    Vault: $($deployment.vaultName)" -ForegroundColor Gray

        try {
          & "./scripts/deploy-vault.ps1" `
            -SubscriptionId $subId `
            -ResourceGroupName $deployment.vaultRG `
            -VaultName $deployment.vaultName `
            -Location $deployment.location

          Write-Host "    ✓ Vault deployed" -ForegroundColor Green
        } catch {
          Write-Host "    ✗ Vault deployment failed: $_" -ForegroundColor Red
          throw
        }
      }
    }

    # Enable backups
    if ($planItemCount -gt 0) {
      Write-Host "  Enabling backups for $planItemCount VM(s)..." -ForegroundColor Yellow

      $successCount = 0
      foreach ($item in $plan.plan) {
        try {
          & "./scripts/apply-backup.ps1" `
            -SubscriptionId $subId `
            -VaultName $item.vaultName `
            -VaultRG $item.vaultRG `
            -VmName $item.vmName `
            -VmRG $item.resourceGroup `
            -PolicyName $item.policyName

          Write-Host "    ✓ $($item.vmName)" -ForegroundColor Green
          $successCount++
        } catch {
          Write-Host "    ✗ $($item.vmName): $_" -ForegroundColor Red
        }
      }

      Write-Host "  Summary: $successCount/$planItemCount VMs protected" -ForegroundColor Yellow
    }

    Write-Host "  ✓ Remediation applied" -ForegroundColor Green
    $remediationResults.successful += @{
      subscription = $subName
      vaults = $vaultCount
      vms = $planItemCount
      status = "applied"
    }

  } catch {
    Write-Host "  ✗ Error: $_" -ForegroundColor Red
    $remediationResults.failed += @{
      subscription = $subName
      reason = $_.Exception.Message
    }
  }

  Write-Host ""
}

# Summary
Write-Host "=== Remediation Summary ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ Successful: $($remediationResults.successful.Count)" -ForegroundColor Green
Write-Host "✗ Failed: $($remediationResults.failed.Count)" -ForegroundColor Red
Write-Host "⊘ Skipped: $($remediationResults.skipped.Count)" -ForegroundColor Yellow
Write-Host ""

if ($remediationResults.failed.Count -gt 0) {
  Write-Host "Failed subscriptions:" -ForegroundColor Red
  foreach ($failure in $remediationResults.failed) {
    Write-Host "  - $($failure.subscription): $($failure.reason)" -ForegroundColor Red
  }
  Write-Host ""
}

if ($DryRun) {
  Write-Host "[DRY RUN] No changes were applied" -ForegroundColor Yellow
  Write-Host "Run again without -DryRun to apply remediation" -ForegroundColor Yellow
}

# Save results
$resultsFile = "./output/plans/remediation-results.json"
$remediationResults | ConvertTo-Json | Out-File -Encoding utf8 $resultsFile
Write-Host ""
Write-Host "Results saved to: $resultsFile" -ForegroundColor Green
