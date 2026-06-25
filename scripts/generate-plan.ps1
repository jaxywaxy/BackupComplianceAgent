param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  throw "SubscriptionId is required."
}

Write-Host "Generating remediation plan..."

$vmsArgs = @("--subscription", $SubscriptionId)
if (-not [string]::IsNullOrWhiteSpace($ResourceGroupName)) {
  $vmsArgs += @("--resource-group", $ResourceGroupName)
}

$vms = az vm list @vmsArgs | ConvertFrom-Json
if (-not $vms) {
  Write-Host "No VMs found in subscription $SubscriptionId." -ForegroundColor Yellow
  exit 0
}

$vaults = az backup vault list --subscription $SubscriptionId | ConvertFrom-Json
if (-not $vaults) {
  throw "No backup vaults found in subscription $SubscriptionId."
}

$protectedVmIds = @{}
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

function Get-PreferredVault($vm) {
  $preferred = $vaults | Where-Object { $_.location -eq $vm.location } | Select-Object -First 1
  if (-not $preferred) {
    $preferred = $vaults | Select-Object -First 1
  }
  return $preferred
}

$output = @()
foreach ($vm in $vms) {
  if (-not $protectedVmIds.ContainsKey($vm.id.ToLower())) {
    $vault = Get-PreferredVault $vm
    if (-not $vault) {
      Write-Host "No backup vault available for VM $($vm.name)." -ForegroundColor Yellow
      continue
    }

    $policy = az backup policy list `
      --vault-name $vault.name `
      --resource-group $vault.resourceGroup `
      | ConvertFrom-Json | Select-Object -First 1

    if (-not $policy) {
      Write-Host "No backup policy found in vault $($vault.name); skipping $($vm.name)." -ForegroundColor Yellow
      continue
    }

    $output += [PSCustomObject]@{
      vmName = $vm.name
      vmId = $vm.id
      resourceGroup = $vm.resourceGroup
      action = "EnableBackup"
      vaultName = $vault.name
      vaultRG = $vault.resourceGroup
      vaultLocation = $vault.location
      policyName = $policy.name
    }
  }
}

$outputDir = "./output/plans"
if (-not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$output | ConvertTo-Json -Depth 5 | Out-File "$outputDir/remediation.json"
Write-Host "Plan written to $outputDir/remediation.json"
