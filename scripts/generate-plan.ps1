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

function Get-VaultMapping($subscriptionId) {
  if (-not $vaultMappings) {
    return @()
  }

  return $vaultMappings.vaults | Where-Object { $_.subscription_id -eq $subscriptionId }
}

function Get-PreferredVault($vm, $subscriptionId, $vaults) {
  $mapping = Get-VaultMapping $subscriptionId
  if ($mapping) {
    foreach ($entry in $mapping) {
      $candidate = $vaults | Where-Object {
        $_.name -eq $entry.vault_name -and $_.resourceGroup -eq $entry.resource_group
      } | Select-Object -First 1
      if ($candidate) {
        return $candidate
      }
    }
  }

  $preferred = $vaults | Where-Object { $_.location -eq $vm.location } | Select-Object -First 1
  if (-not $preferred) {
    $preferred = $vaults | Select-Object -First 1
  }

  return $preferred
}

function Get-VaultPolicy($vault, $policyName) {
  try {
    return az backup policy show `
      --vault-name $vault.name `
      --resource-group $vault.resourceGroup `
      --name $policyName `
      2>$null | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Get-AnyVaultPolicy($vault) {
  try {
    $policies = az backup policy list `
      --vault-name $vault.name `
      --resource-group $vault.resourceGroup `
      2>$null | ConvertFrom-Json
    if ($policies -and $policies.Count -gt 0) {
      return $policies[0]
    }
  } catch {
  }
  return $null
}

function Get-PolicyName($normalizedEnvironment, $vault) {
  $rule = Get-BackupRuleOrDefault $backupRules $normalizedEnvironment
  if ($rule -and $rule.policy -and $rule.policy -ne 'default') {
    return $rule.policy
  }

  $mapping = Get-VaultMapping $SubscriptionId | Where-Object {
    $_.vault_name -eq $vault.name -and $_.resource_group -eq $vault.resourceGroup
  } | Select-Object -First 1

  if ($mapping -and $mapping.default_policy) {
    return $mapping.default_policy
  }

  if ($rule -and $rule.policy -eq 'default') {
    $candidatePolicyName = 'DefaultPolicy'
    if (Get-VaultPolicy $vault $candidatePolicyName) {
      return $candidatePolicyName
    }

    $anyPolicy = Get-AnyVaultPolicy $vault
    if ($anyPolicy -and $anyPolicy.name) {
      return $anyPolicy.name
    }
  }

  return $null
}

function Evaluate-Environment($environment) {
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

Write-Host "Generating remediation plan..."

if (-not (Get-Module -Name powershell-yaml -ListAvailable)) {
  Write-Host "Installing powershell-yaml module..."
  Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}

Import-Module powershell-yaml -Force

$backupRules = $null
$vaultMappings = $null
try {
  $config = Load-YamlConfig './config/backup-rules.yaml'
  $backupRules = $config.backup_rules
} catch {
  Write-Host "Unable to load backup rules config: $_" -ForegroundColor Yellow
}

try {
  $vaultMappings = Load-YamlConfig './config/vault-mapping.yaml'
} catch {
  Write-Host "Unable to load vault mapping config: $_" -ForegroundColor Yellow
}

$vmsArgs = @("--subscription", $SubscriptionId)
if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
  $vmsArgs += @("--resource-group", $ResourceGroupName)
}

$vms = az vm list @vmsArgs | ConvertFrom-Json

$planResult = [PSCustomObject]@{
  vaultDeployments = @()
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
    notificationRecipient = $defaultNotificationRecipient
  }
}

$vaults = az backup vault list --subscription $SubscriptionId | ConvertFrom-Json
if (-not $vaults) {
  Write-Host "No Recovery Services vaults found in subscription $SubscriptionId." -ForegroundColor Yellow
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
        notificationRecipient = $defaultNotificationRecipient
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
        notificationRecipient = $defaultNotificationRecipient
      }
      continue
    }

    $decision = Evaluate-Environment $environment
    $normalizedEnvironment = Normalize-Environment $environment

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
        notificationRecipient = $defaultNotificationRecipient
      }
      continue
    }

    $vault = $null
    if ($vaults) {
      $vault = Get-PreferredVault $vm $SubscriptionId $vaults
    }

    if (-not $vault) {
      $mapping = Get-VaultMapping $SubscriptionId
      $mappedVault = if ($mapping) { $mapping | Select-Object -First 1 } else { $null }

      $vaultName = if ($mappedVault) { $mappedVault.vault_name } else { "rsv-backup-$($vm.location.Substring(0,3))-001" }
      $vaultRG = if ($mappedVault) { $mappedVault.resource_group } else { 'rg-backup-shared' }

      Write-Host "$($vm.name) => VAULT DEPLOYMENT NEEDED ($vaultName in $vaultRG)" -ForegroundColor Cyan

      $deploymentKey = "$vaultName-$vaultRG"
      $existingDeployment = $planResult.vaultDeployments | Where-Object { $_.deploymentKey -eq $deploymentKey }

      if (-not $existingDeployment) {
        $planResult.vaultDeployments += [PSCustomObject]@{
          deploymentKey = $deploymentKey
          vaultName = $vaultName
          vaultRG = $vaultRG
          location = $vm.location
          vmName = $vm.name
          subscriptionId = $SubscriptionId
        }
      }

      $planResult.plan += [PSCustomObject]@{
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
        action = 'EnableBackup'
        vaultName = $vaultName
        vaultRG = $vaultRG
        vaultLocation = $vm.location
        policyName = $null
        ownerNotification = "Vault deployment required before backup can be enabled."
        notificationRecipient = $defaultNotificationRecipient
        decision = $decision
      }
      continue
    }

    $policyName = Get-PolicyName $normalizedEnvironment $vault
    if (-not $policyName) {
      Write-Host "$($vm.name) => NO BACKUP POLICY FOUND FOR VAULT $($vault.name)" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = 'No backup policy specified for selected vault.'
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
        vaultName = $vault.name
        vaultResourceGroup = $vault.resourceGroup
        notificationRecipient = $defaultNotificationRecipient
      }
      continue
    }

    $policy = Get-VaultPolicy $vault $policyName
    if (-not $policy) {
      Write-Host "$($vm.name) => POLICY $policyName NOT FOUND IN VAULT $($vault.name); falling back to first available policy" -ForegroundColor Yellow
      $policy = Get-AnyVaultPolicy $vault
      if ($policy -and $policy.name) {
        $policyName = $policy.name
      }
    }

    if (-not $policy) {
      Write-Host "$($vm.name) => POLICY $policyName NOT FOUND IN VAULT $($vault.name)" -ForegroundColor Yellow
      $planResult.notifications += [PSCustomObject]@{
        level = 'Warning'
        message = "Backup policy '$policyName' not found in selected vault."
        vmName = $vm.name
        vmId = $vm.id
        resourceGroup = $vm.resourceGroup
        owner = $owner
        environment = $environment
        vaultName = $vault.name
        vaultResourceGroup = $vault.resourceGroup
        policyName = $policyName
        notificationRecipient = $defaultNotificationRecipient
      }
      continue
    }

    Write-Host "$($vm.name) => REMEDIATION PLAN GENERATED" -ForegroundColor Red
    $recipient = $defaultNotificationRecipient

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
      policyName = $policyName
      ownerNotification = "Notify owner '$recipient' about backup enablement."
      notificationRecipient = $recipient
      decision = $decision
    }
  }
}

$outputDir = './output/plans'
if (-not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$jsonPath = "$outputDir/remediation.json"
$planResult | ConvertTo-Json -Depth 6 | Out-File -Encoding utf8 $jsonPath
Write-Host "Plan written to $jsonPath"
Write-Host "Vault deployments: $($planResult.vaultDeployments.Count); Plan items: $($planResult.plan.Count); Notifications: $($planResult.notifications.Count)"

$markdownPath = "$outputDir/remediation.md"
$md = @()
$md += "# Backup Remediation Plan"
$md += ""
$md += "Generated: $(Get-Date -Format 'u')"
$md += ""
$md += "## Summary"
$md += "- Vault deployments required: $($planResult.vaultDeployments.Count)"
$md += "- Total plan items: $($planResult.plan.Count)"
$md += "- Total notifications: $($planResult.notifications.Count)"
$md += ""

if ($planResult.vaultDeployments.Count -gt 0) {
  $md += "## Vault Deployments Required"
  foreach ($deployment in $planResult.vaultDeployments | Select-Object -First 20) {
    $md += "- **Vault:** $($deployment.vaultName)"
    $md += "  - Resource Group: $($deployment.vaultRG)"
    $md += "  - Location: $($deployment.location)"
    $md += "  - Triggered by VM: $($deployment.vmName)"
    $md += ""
  }
  if ($planResult.vaultDeployments.Count -gt 20) {
    $md += "- And $($planResult.vaultDeployments.Count - 20) more vault deployments..."
    $md += ""
  }
}

if ($planResult.plan.Count -gt 0) {
  $md += "## Remediation Items"
  foreach ($item in $planResult.plan | Select-Object -First 20) {
    $md += "- **VM:** $($item.vmName)"
    $md += "  - Resource Group: $($item.resourceGroup)"
    $md += "  - Vault: $($item.vaultName) ($($item.vaultRG))"
    $md += "  - Policy: $($item.policyName)"
    $md += "  - Environment: $($item.environment)"
    $md += "  - Owner: $($item.owner)"
    $md += "  - Decision: $($item.decision)"
    $md += ""
  }
  if ($planResult.plan.Count -gt 20) {
    $md += "- And $($planResult.plan.Count - 20) more remediation items..."
    $md += ""
  }
}

if ($planResult.notifications.Count -gt 0) {
  $md += "## Notifications"
  foreach ($note in $planResult.notifications | Select-Object -First 20) {
    $md += "- **$($note.level)**: $($note.message)"
    if ($note.vmName) { $md += "  - VM: $($note.vmName)" }
    if ($note.resourceGroup) { $md += "  - Resource Group: $($note.resourceGroup)" }
    if ($note.owner) { $md += "  - Owner: $($note.owner)" }
    if ($note.environment) { $md += "  - Environment: $($note.environment)" }
    $md += ""
  }
  if ($planResult.notifications.Count -gt 20) {
    $md += "- And $($planResult.notifications.Count - 20) more notifications..."
    $md += ""
  }
}

$md -join "`n" | Out-File -Encoding utf8 -FilePath $markdownPath
Write-Host "Markdown plan written to $markdownPath"
