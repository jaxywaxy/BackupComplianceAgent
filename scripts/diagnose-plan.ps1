param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  throw "SubscriptionId is required."
}

Write-Host "=== Backup Remediation Plan Diagnostics ===" -ForegroundColor Cyan
Write-Host ""

# Check modules
Write-Host "Step 1: Checking PowerShell modules..." -ForegroundColor Yellow
if (-not (Get-Module -Name powershell-yaml -ListAvailable)) {
  Write-Host "Installing powershell-yaml module..." -ForegroundColor Yellow
  Install-Module -Name powershell-yaml -Force -Scope CurrentUser
}
Import-Module powershell-yaml -Force
Write-Host "✓ powershell-yaml module loaded" -ForegroundColor Green
Write-Host ""

# Load configs
Write-Host "Step 2: Loading configuration files..." -ForegroundColor Yellow

$backupRules = $null
try {
  $config = Get-Content -Raw -Path './config/backup-rules.yaml' | ConvertFrom-Yaml
  $backupRules = $config.backup_rules
  Write-Host "✓ Loaded backup rules" -ForegroundColor Green
  if ($backupRules) {
    if ($backupRules.GetType().Name -eq "Hashtable") {
      Write-Host "  Rules: $($backupRules.Keys -join ', ')" -ForegroundColor Gray
    } else {
      Write-Host "  Rules: $($backupRules.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
    }
  }
} catch {
  Write-Host "✗ Failed to load backup rules: $_" -ForegroundColor Red
}

$vaultMappings = $null
try {
  $vaultMappings = Get-Content -Raw -Path './config/vault-mapping.yaml' | ConvertFrom-Yaml
  Write-Host "✓ Loaded vault mappings" -ForegroundColor Green
  if ($vaultMappings.vaults) {
    Write-Host "  Mapped vaults: $($vaultMappings.vaults.Count)" -ForegroundColor Gray
  }
} catch {
  Write-Host "✗ Failed to load vault mappings: $_" -ForegroundColor Red
}

Write-Host ""

# First check Azure auth
Write-Host "Step 2b: Checking Azure authentication..." -ForegroundColor Yellow
try {
  $account = az account show --output json 2>&1
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($account)) {
    Write-Host "✗ Not authenticated to Azure. Run 'az login' first" -ForegroundColor Red
    Write-Host "  Error: $account" -ForegroundColor Red
    exit 1
  }

  # Try to parse the JSON
  $currentSub = $account | ConvertFrom-Json -ErrorAction Stop
  Write-Host "✓ Authenticated as: $($currentSub.user.name)" -ForegroundColor Green
  Write-Host "  Current subscription: $($currentSub.name) ($($currentSub.id))" -ForegroundColor Gray

  if ($currentSub.id -ne $SubscriptionId) {
    Write-Host "⚠ Target subscription differs from current" -ForegroundColor Yellow
  }
} catch {
  Write-Host "⚠ Could not verify authentication: $_" -ForegroundColor Yellow
  Write-Host "  Continuing with provided subscription ID..." -ForegroundColor Yellow
}

Write-Host ""

# Get VMs
Write-Host "Step 3: Scanning VMs..." -ForegroundColor Yellow
$vmsArgs = @("--subscription", $SubscriptionId, "--output", "json")
if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
  $vmsArgs += @("--resource-group", $ResourceGroupName)
}

try {
  $vmOutput = az vm list @vmsArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    Write-Host "✗ Failed to list VMs:" -ForegroundColor Red
    Write-Host "  $vmOutput" -ForegroundColor Red
    exit 1
  }

  if ([string]::IsNullOrWhiteSpace($vmOutput) -or $vmOutput -eq "[]") {
    Write-Host "✗ No VMs found in subscription" -ForegroundColor Red
    exit 1
  }

  $vms = $vmOutput | ConvertFrom-Json
} catch {
  Write-Host "✗ Error parsing VM list: $_" -ForegroundColor Red
  Write-Host "  Raw output: $vmOutput" -ForegroundColor Red
  exit 1
}

Write-Host "✓ Found $($vms.Count) VM(s)" -ForegroundColor Green
Write-Host ""

# Get vaults
Write-Host "Step 4: Checking Recovery Services Vaults..." -ForegroundColor Yellow
$vaults = az backup vault list --subscription $SubscriptionId | ConvertFrom-Json

if (-not $vaults) {
  Write-Host "✗ No vaults found in subscription" -ForegroundColor Red
} else {
  Write-Host "✓ Found $($vaults.Count) vault(s)" -ForegroundColor Green
  foreach ($vault in $vaults) {
    Write-Host "  - $($vault.name) in $($vault.resourceGroup) @ $($vault.location)" -ForegroundColor Gray
  }
}

Write-Host ""

# Check protected VMs
Write-Host "Step 5: Checking protected VMs..." -ForegroundColor Yellow
$protectedVmIds = @{}
if ($vaults) {
  foreach ($vault in $vaults) {
    $items = az backup item list `
      --vault-name $vault.name `
      --resource-group $vault.resourceGroup `
      2>$null | ConvertFrom-Json

    if ($items) {
      Write-Host "  Vault '$($vault.name)' protects $($items.Count) item(s)" -ForegroundColor Gray
      foreach ($item in $items) {
        $sourceId = $item.properties.sourceResourceId
        if ($sourceId) {
          $protectedVmIds[$sourceId.ToLower()] = $true
        }
      }
    }
  }
}

Write-Host "✓ $($protectedVmIds.Count) VM(s) already protected" -ForegroundColor Green
Write-Host ""

# Analyze each VM
Write-Host "Step 6: Analyzing each VM..." -ForegroundColor Yellow
Write-Host ""

function Get-TagValue($vm, $tagName) {
  if (-not $vm.tags) {
    return $null
  }
  if ($vm.tags.PSObject.Properties.Name -contains $tagName) {
    return $vm.tags.$tagName
  }
  return $null
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

$vmSummary = @()

foreach ($vm in $vms) {
  $owner = Get-TagValue $vm 'owner'
  $environment = Get-TagValue $vm 'environment'
  $vmIdLower = $vm.id.ToLower()
  $backupEnabled = $protectedVmIds.ContainsKey($vmIdLower)

  Write-Host "VM: $($vm.name)" -ForegroundColor Cyan
  Write-Host "  Location: $($vm.location)"
  Write-Host "  Resource Group: $($vm.resourceGroup)"

  if ($backupEnabled) {
    Write-Host "  Backup Status: ✓ ALREADY PROTECTED" -ForegroundColor Green
    $vmSummary += [PSCustomObject]@{
      VM = $vm.name
      Owner = $owner
      Environment = $environment
      Status = 'PROTECTED'
      Reason = 'Backup already enabled'
    }
    Write-Host ""
    continue
  }

  Write-Host "  Backup Status: ✗ NOT PROTECTED" -ForegroundColor Red

  # Check tags
  if ([string]::IsNullOrWhiteSpace($owner)) {
    Write-Host "  Owner Tag: ✗ MISSING" -ForegroundColor Red
    $vmSummary += [PSCustomObject]@{
      VM = $vm.name
      Owner = $owner
      Environment = $environment
      Status = 'SKIPPED'
      Reason = 'Missing owner tag'
    }
    Write-Host ""
    continue
  } else {
    Write-Host "  Owner Tag: ✓ $owner" -ForegroundColor Green
  }

  if ([string]::IsNullOrWhiteSpace($environment)) {
    Write-Host "  Environment Tag: ✗ MISSING" -ForegroundColor Red
    $vmSummary += [PSCustomObject]@{
      VM = $vm.name
      Owner = $owner
      Environment = $environment
      Status = 'SKIPPED'
      Reason = 'Missing environment tag'
    }
    Write-Host ""
    continue
  } else {
    Write-Host "  Environment Tag: ✓ $environment" -ForegroundColor Green
  }

  # Check backup rule
  $normalizedEnvironment = Normalize-Environment $environment
  Write-Host "  Normalized Environment: $normalizedEnvironment"

  $ruleFound = $false
  $rule = $null

  if ($backupRules) {
    if ($backupRules -is [hashtable]) {
      if ($backupRules.ContainsKey($normalizedEnvironment)) {
        $rule = $backupRules[$normalizedEnvironment]
        $ruleFound = $true
      }
    } else {
      if ($backupRules.PSObject.Properties.Name -contains $normalizedEnvironment) {
        $rule = $backupRules.$normalizedEnvironment
        $ruleFound = $true
      }
    }
  }

  if ($ruleFound) {
    Write-Host "  Backup Rule: ✓ Found" -ForegroundColor Green
    Write-Host "    Required: $($rule.required)"
    Write-Host "    Policy: $($rule.policy)"

    if ($rule.required -eq $true) {
      Write-Host "  Decision: ✓ NEEDS BACKUP" -ForegroundColor Green
      $vmSummary += [PSCustomObject]@{
        VM = $vm.name
        Owner = $owner
        Environment = $environment
        Status = 'NEEDS_BACKUP'
        Reason = "Backup required for $normalizedEnvironment environment"
      }
    } else {
      Write-Host "  Decision: ℹ REVIEW ONLY" -ForegroundColor Yellow
      $vmSummary += [PSCustomObject]@{
        VM = $vm.name
        Owner = $owner
        Environment = $environment
        Status = 'REVIEW'
        Reason = "Backup not required for $normalizedEnvironment environment"
      }
    }
  } else {
    Write-Host "  Backup Rule: ✗ NOT FOUND" -ForegroundColor Red
    Write-Host "  Decision: ℹ REVIEW ONLY" -ForegroundColor Yellow
    $vmSummary += [PSCustomObject]@{
      VM = $vm.name
      Owner = $owner
      Environment = $environment
      Status = 'REVIEW'
      Reason = "No rule for environment '$normalizedEnvironment'"
    }
  }

  Write-Host ""
}

# Summary
Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host ""

$vmSummary | Format-Table -AutoSize

$needsBackup = $vmSummary | Where-Object { $_.Status -eq 'NEEDS_BACKUP' } | Measure-Object | Select-Object -ExpandProperty Count
$protected = $vmSummary | Where-Object { $_.Status -eq 'PROTECTED' } | Measure-Object | Select-Object -ExpandProperty Count
$skipped = $vmSummary | Where-Object { $_.Status -eq 'SKIPPED' } | Measure-Object | Select-Object -ExpandProperty Count
$review = $vmSummary | Where-Object { $_.Status -eq 'REVIEW' } | Measure-Object | Select-Object -ExpandProperty Count

Write-Host ""
Write-Host "Results:" -ForegroundColor Cyan
Write-Host "  Protected VMs: $protected" -ForegroundColor Green
Write-Host "  VMs needing backup: $needsBackup" -ForegroundColor Yellow
Write-Host "  VMs skipped (missing tags): $skipped" -ForegroundColor Red
Write-Host "  VMs requiring review: $review" -ForegroundColor Yellow

if ($needsBackup -eq 0) {
  Write-Host ""
  Write-Host "⚠ No VMs need backup remediation." -ForegroundColor Yellow
  Write-Host ""
  Write-Host "Possible reasons:" -ForegroundColor Yellow
  Write-Host "1. All VMs already have backups enabled" -ForegroundColor Gray
  Write-Host "2. VMs missing required tags (owner, environment)" -ForegroundColor Gray
  Write-Host "3. VM environments don't match backup rules" -ForegroundColor Gray
  Write-Host "4. Backup policy is set to 'required: false' in backup-rules.yaml" -ForegroundColor Gray
}

Write-Host ""
