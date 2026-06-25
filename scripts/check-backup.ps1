param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId)) {
  throw "SubscriptionId is required."
}

Write-Host "Checking backup compliance..."

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
  Write-Host "No backup vaults found in subscription $SubscriptionId." -ForegroundColor Yellow
  exit 0
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

$results = @()
foreach ($vm in $vms) {
  $vmId = $vm.id.ToLower()
  $compliant = $protectedVmIds.ContainsKey($vmId)

  $results += [PSCustomObject]@{
    vmName = $vm.name
    resourceGroup = $vm.resourceGroup
    location = $vm.location
    vmId = $vm.id
    compliant = $compliant
  }

  if ($compliant) {
    Write-Host "$($vm.name) => COMPLIANT" -ForegroundColor Green
  }
  else {
    Write-Host "$($vm.name) => NON-COMPLIANT" -ForegroundColor Red
  }
}

$outputDir = "./output/reports"
if (-not (Test-Path $outputDir)) {
  New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

$results | ConvertTo-Json -Depth 5 | Out-File "$outputDir/compliance.json"
Write-Host "Compliance report written to $outputDir/compliance.json"
