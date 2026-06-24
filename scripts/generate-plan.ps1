param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

$output = @()

$vms = az vm list `
  --subscription $SubscriptionId `
  --resource-group $ResourceGroupName `
  | ConvertFrom-Json

$vault = az backup vault list `
  --subscription $SubscriptionId `
  | ConvertFrom-Json | Select-Object -First 1

foreach ($vm in $vms) {

  $items = az backup item list `
    --vault-name $vault.name `
    --resource-group $vault.resourceGroup `
    | ConvertFrom-Json

  $exists = $items | Where-Object {
    $_.properties.sourceResourceId -like "*$($vm.name)*"
  }

  if (!$exists) {
    $output += [PSCustomObject]@{
      vmName = $vm.name
      action = "EnableBackup"
      vault = $vault.name
    }
  }
}

$output | ConvertTo-Json | Out-File ./output/plans/remediation.json

Write-Host "Plan written to output/plans/remediation.json"
