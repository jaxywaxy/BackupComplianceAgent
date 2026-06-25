param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  throw "SubscriptionId is required."
}

function Get-TagValue($vm, $tagName) {
  if (-not $vm.tags) {
    return $null
  }

  if ($vm.tags.PSObject.Properties.Name -contains $tagName) {
    return $vm.tags.$tagName
  }

  return $null
}

function Evaluate-Environment($environment) {
  if (-not $environment) {
    return 'Review'
  }
  switch ($environment.ToLower()) {
    'prod' { return 'EnableBackup' }
    'production' { return 'EnableBackup' }
    'stage' { return 'EnableBackup' }
    'staging' { return 'EnableBackup' }
    'uat' { return 'EnableBackup' }
    'preprod' { return 'EnableBackup' }
    'qa' { return 'EnableBackup' }
    'dev' { return 'EnableBackup' }
    'development' { return 'EnableBackup' }
    'test' { return 'EnableBackup' }
    'sandbox' { return 'EnableBackup' }
    default { return 'Review' }
  }
}

Write-Host "Generating remediation plan..."

$vmsArgs = @("--subscription", $SubscriptionId)
if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
  $vmsArgs += @("--resource-group", $ResourceGroupName)
}

$vms = az vm list @vmsArgs | ConvertFrom-Json

$planResult = [PSCustomObject]@{
  plan = @()
  notifications = @()
}

if (-not $vms) {
  Write-Host "No VMs found in subscription $SubscriptionId." -ForegroundColor Yellow
  $planResult.notifications += [PSCustomObject]@{
    level = 'Warning'
    message = 'No virtual machines were discovered in subscription.'
    subscriptionId = $SubscriptionId
    resourceGroup = $ResourceGroupName
  }
}

$vaults = az backup vault list --subscription $SubscriptionId | ConvertFrom-Json
if (-not $vaults) {
  Write-Host "No Recovery Services vaults found in subscription $SubscriptionId." -ForegroundColor Yellow
  $planResult.notifications += [PSCustomObject]@{
    level = 'Error'
    message = 'No Recovery Services vaults found in subscription.'
    subscriptionId = $SubscriptionId
  }
}

$protectedVmIds = @{}
if ($vaults) {
  foreach ($vault in $vaults) {
    $items = az backup item list `
      --vault-name $vault.name `
      --resource-group $vault.resourceGroup `
      | ConvertFrom-Json

    foreach ($item in $items) {
      $sourceId = $item.properties.sourceResourceId
      if ($sourceId) {
        $protectedVmIds[$sourceId.ToLower()] = $true
      }
    }
  }
}

function Get-PreferredVault($vm) {
  $preferred = $vaults | Where-Object { $_.location -eq $vm.location } | Select-Object -First 1
  if (-not $preferred) {
    $preferred = $vaults | Select-Object -First 1
  }
  return $preferred
}

if ($vms) {
  foreach ($vm in $vms) {
    $owner = Get-TagValue $vm 'owner'
    $environment = Get-TagValue $vm 'environment'
    $vmIdLower = $vm.id.ToLower()
    $backupEnabled = $protectedVmIds.ContainsKey($vmIdLower)

    if ($backupEnabled) {
      Write-Host "$($vm.name) => COMPLIANT" -ForegroundColor Green
      continue
    }

    if ([string]::IsNullOrWhiteSpace($owner)) {
      Write-Host "$($vm.name) => MISSING OWNER TAG" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = 'Missing owner tag.'
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
      }
      continue
    }

    if ([string]::IsNullOrWhiteSpace($environment)) {
      Write-Host "$($vm.name) => MISSING ENVIRONMENT TAG" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = 'Missing environment tag.'
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
      }
      continue
    }

    $decision = Evaluate-Environment $environment
    if ($decision -ne 'EnableBackup') {
      Write-Host "$($vm.name) => REVIEW REQUIRED for environment '$environment'" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = "Review required for environment '$environment'."
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
        decision = $decision
      }
      continue
    }

    $vault = Get-PreferredVault $vm
    if (-not $vault) {
      Write-Host "$($vm.name) => NO RECOVERY SERVICES VAULT AVAILABLE" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = 'No Recovery Services vault available for VM.'
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
      }
      continue
    }

    $policy = az backup policy list `
      --vault-name $vault.name `
      --resource-group $vault.resourceGroup `
      | ConvertFrom-Json | Select-Object -First 1

    if (-not $policy) {
      Write-Host "$($vm.name) => NO BACKUP POLICY IN VAULT $($vault.name)" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = 'No backup policy found in selected vault.'
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
        vaultName = $vault.name
        vaultResourceGroup = $vault.resourceGroup
      }
      continue
    }

    Write-Host "$($vm.name) => REMEDIATION PLAN GENERATED" -ForegroundColor Red
    $planResult.plan += [PSCustomObject]@{
      vmName = $vm.name
      vmId = $vm.id
      resourceGroup = $vm.resourceGroup
      owner = $owner
      environment = $environment
      action = 'EnableBackup'
      vaultName = $vault.name
      vaultRG = $vault.resourceGroup
      vaultLocation = $vault.location
      policyName = $policy.name
      decision = $decision
    }
  }
}

$outputDir = './output/plans'
if (-not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$planResult | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 "$outputDir/remediation.json"
Write-Host "Plan written to $outputDir/remediation.json"
Write-Host "Plan items: $($planResult.plan.Count); Notifications: $($planResult.notifications.Count)"
