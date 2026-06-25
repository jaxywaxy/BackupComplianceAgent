param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  throw "SubscriptionId is required."
}

$defaultNotificationRecipient = 'jacqui.rennie@slingshot.co.nz'

function Get-TagValue($vm, $tagName) {
  if (-not $vm.tags) {
    return $null
  }

  if ($vm.tags.PSObject.Properties.Name -contains $tagName) {
    return $vm.tags.$tagName
  }

  return $null
}

function Load-YamlConfig($path) {
  if (-not (Test-Path $path)) {
    throw "Configuration file not found: $path"
  }

  $content = Get-Content -Raw -Path $path
  return $content | ConvertFrom-Yaml
}

function Normalize-Environment($environment) {
  if (-not $environment) {
    return $null
  }

  switch ($environment.ToLower()) {
    'prod' { return 'prod' }
    'production' { return 'prod' }
    'nonprod' { return 'nonprod' }
    'stage' { return 'nonprod' }
    'staging' { return 'nonprod' }
    'uat' { return 'nonprod' }
    'preprod' { return 'nonprod' }
    'qa' { return 'nonprod' }
    'dev' { return 'nonprod' }
    'development' { return 'nonprod' }
    'test' { return 'nonprod' }
    'sandbox' { return 'nonprod' }
    default { return $environment.ToLower() }
  }
}

function Get-BackupRule($rules, $key) {
  if (-not $rules) {
    return $null
  }

  if ($rules.PSObject.Properties.Name -contains $key) {
    return $rules.$key
  }

  return $null
}

function Get-BackupRuleOrDefault($rules, $key) {
  $rule = Get-BackupRule $rules $key
  if ($rule) {
    return $rule
  }

  return Get-BackupRule $rules 'default'
}

function Evaluate-Environment($environment, $backupRules) {
  if (-not $environment) {
    return 'Review'
  }

  $normalized = Normalize-Environment $environment
  $rule = Get-BackupRuleOrDefault $backupRules $normalized

  if (-not $rule) {
    return 'Review'
  }

  if ($rule.required -eq $true) {
    return 'EnableBackup'
  }

  return 'Review'
}

Write-Host "Checking backup compliance..."

$backupRules = $null
try {
  $config = Load-YamlConfig './config/backup-rules.yaml'
  $backupRules = $config.backup_rules
} catch {
  Write-Host "Unable to load backup rules config: $_" -ForegroundColor Yellow
}

$vmsArgs = @("--subscription", $SubscriptionId)
if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
  $vmsArgs += @("--resource-group", $ResourceGroupName)
}

$vms = az vm list @vmsArgs | ConvertFrom-Json

$report = [PSCustomObject]@{
  results = @()
  notifications = @()
}

if (-not $vms) {
  Write-Host "No VMs found in subscription $SubscriptionId." -ForegroundColor Yellow
  $report.notifications += [PSCustomObject]@{
    level = "Warning"
    message = "No virtual machines were discovered in subscription."
    subscriptionId = $SubscriptionId
    resourceGroup = $ResourceGroupName
  }
}

$vaults = az backup vault list --subscription $SubscriptionId | ConvertFrom-Json
if (-not $vaults) {
  Write-Host "No backup vaults found in subscription $SubscriptionId." -ForegroundColor Yellow
  $report.notifications += [PSCustomObject]@{
    level = "Error"
    message = "No Recovery Services vaults found in subscription."
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

if ($vms) {
  foreach ($vm in $vms) {
    $owner = Get-TagValue $vm 'owner'
    $environment = Get-TagValue $vm 'environment'
    $vmId = $vm.id.ToLower()
    $backupEnabled = $protectedVmIds.ContainsKey($vmId)
    $decision = $null
    $reason = $null
    $ruleLabel = $null

    if ($backupEnabled) {
      $decision = 'Compliant'
      $reason = 'Backup protection already enabled.'
      Write-Host "$($vm.name) => COMPLIANT" -ForegroundColor Green
    }
    else {
      if ([string]::IsNullOrWhiteSpace($owner)) {
        $decision = 'MissingOwner'
        $reason = 'Missing owner tag.'
        Write-Host "$($vm.name) => MISSING OWNER TAG" -ForegroundColor Yellow
      }
      elseif ([string]::IsNullOrWhiteSpace($environment)) {
        $decision = 'MissingEnvironment'
        $reason = 'Missing environment tag.'
        Write-Host "$($vm.name) => MISSING ENVIRONMENT TAG" -ForegroundColor Yellow
      }
      else {
        $decision = Evaluate-Environment $environment $backupRules
        $ruleLabel = Normalize-Environment $environment

        if ($decision -eq 'EnableBackup') {
          Write-Host "$($vm.name) => NON-COMPLIANT, remediation required" -ForegroundColor Red
          $reason = "Backup required for environment '$environment' (rule: $ruleLabel). Notify owner '$owner'."
        }
        else {
          Write-Host "$($vm.name) => REVIEW REQUIRED for environment '$environment'" -ForegroundColor Yellow
          $reason = "Review required for environment '$environment' (rule: $ruleLabel)."
        }
      }
    }

    $report.results += [PSCustomObject]@{
      vmName = $vm.name
      resourceGroup = $vm.resourceGroup
      location = $vm.location
      vmId = $vm.id
      owner = $owner
      environment = $environment
      backupEnabled = $backupEnabled
      decision = $decision
      rule = $ruleLabel
      reason = $reason
      compliant = ($backupEnabled -eq $true)
    }

    if ($decision -ne 'Compliant') {
      $notificationRecipient = $defaultNotificationRecipient
      $ownerNotificationMessage = if ($decision -eq 'EnableBackup') { "Notify owner '$notificationRecipient' about backup enablement." } else { $null }
      $notification = [PSCustomObject]@{
        level = if ($decision -eq 'EnableBackup') { 'Alert' } else { 'Warning' }
        message = $reason
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
        decision = $decision
        ownerNotification = $ownerNotificationMessage
        notificationRecipient = $notificationRecipient
      }
      $report.notifications += $notification
    }
  }
}

$outputDir = "./output/reports"
if (-not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$report | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 "$outputDir/compliance.json"
Write-Host "Compliance report written to $outputDir/compliance.json"
Write-Host "Results: $($report.results.Count); Notifications: $($report.notifications.Count)"
