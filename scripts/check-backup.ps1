param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName
)

Write-Host "Checking backup compliance..."

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

  $matched = $items | Where-Object {
    $_.properties.sourceResourceId -like "*$($vm.name)*"
  }

  if (!$matched) {
    Write-Host "$($vm.name) => NON-COMPLIANT" -ForegroundColor Red
  }
  else {
    Write-Host "$($vm.name) => COMPLIANT" -ForegroundColor Green
  }
}
