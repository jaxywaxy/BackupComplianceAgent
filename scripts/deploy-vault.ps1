param(
  [string]$SubscriptionId,
  [string]$ResourceGroupName,
  [string]$VaultName,
  [string]$Location = 'australiaeast'
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($ResourceGroupName) -or [string]::IsNullOrWhiteSpace($VaultName)) {
  throw "SubscriptionId, ResourceGroupName, and VaultName are required."
}

Write-Host "Deploying Recovery Services Vault: $VaultName in $ResourceGroupName..."

# Ensure resource group exists
$rg = az group show --name $ResourceGroupName --subscription $SubscriptionId --output json 2>$null
if (-not $rg) {
  Write-Host "Creating resource group: $ResourceGroupName in location $Location"
  az group create `
    --name $ResourceGroupName `
    --location $Location `
    --subscription $SubscriptionId
}

# Deploy vault using bicep
$bicepPath = './infra/main.bicep'
if (-not (Test-Path $bicepPath)) {
  throw "Bicep file not found: $bicepPath"
}

Write-Host "Deploying vault using bicep template..."
az deployment group create `
  --subscription $SubscriptionId `
  --resource-group $ResourceGroupName `
  --template-file $bicepPath `
  --parameters `
    location=$Location `
    vaultName=$VaultName

if ($LASTEXITCODE -ne 0) {
  throw "Failed to deploy vault $VaultName"
}

Write-Host "Vault deployed successfully: $VaultName" -ForegroundColor Green

# Wait for vault to be fully ready
Write-Host "Waiting for vault to be accessible..."
$maxAttempts = 10
$attempt = 0
while ($attempt -lt $maxAttempts) {
  $vault = az backup vault list `
    --subscription $SubscriptionId `
    --resource-group $ResourceGroupName `
    --query "[?name=='$VaultName']" `
    --output json `
    2>$null | ConvertFrom-Json

  if ($vault -and $vault.Count -gt 0) {
    Write-Host "Vault is ready."
    break
  }

  $attempt++
  if ($attempt -lt $maxAttempts) {
    Write-Host "Waiting for vault... (attempt $attempt/$maxAttempts)"
    Start-Sleep -Seconds 5
  }
}

if ($attempt -eq $maxAttempts) {
  Write-Host "Warning: Vault may not be fully ready yet. Proceeding anyway." -ForegroundColor Yellow
}

# Create default backup policies for the vault
Write-Host ""
Write-Host "Creating backup policies..." -ForegroundColor Cyan

$policyScript = './scripts/create-vault-policies.ps1'
if (Test-Path $policyScript) {
  try {
    & $policyScript -SubscriptionId $SubscriptionId -VaultName $VaultName -VaultRG $ResourceGroupName
  } catch {
    Write-Host "⚠️  Warning: Failed to create policies automatically: $_" -ForegroundColor Yellow
    Write-Host "Policies can be created manually by running:" -ForegroundColor Yellow
    Write-Host "  pwsh ./scripts/create-vault-policies.ps1 -SubscriptionId '$SubscriptionId' -VaultName '$VaultName' -VaultRG '$ResourceGroupName'" -ForegroundColor Yellow
  }
} else {
  Write-Host "⚠️  Policy creation script not found at $policyScript" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "✓ Vault deployment complete" -ForegroundColor Green
