param(
  [switch]$IncludeDetails
)

Write-Host "=== Discovering Azure Subscriptions ===" -ForegroundColor Cyan
Write-Host ""

# Get all subscriptions
$subscriptions = az account list --output json | ConvertFrom-Json

if (-not $subscriptions) {
  Write-Host "✗ No subscriptions found or not authenticated" -ForegroundColor Red
  Write-Host "Run 'az login' first" -ForegroundColor Yellow
  exit 1
}

Write-Host "Found $($subscriptions.Count) subscription(s):" -ForegroundColor Green
Write-Host ""

$subscriptionList = @()

foreach ($sub in $subscriptions) {
  $name = $sub.name
  $id = $sub.id
  $state = $sub.state
  $tenantId = $sub.tenantId

  Write-Host "Subscription: $name" -ForegroundColor Cyan
  Write-Host "  ID: $id" -ForegroundColor Gray
  Write-Host "  State: $state" -ForegroundColor Gray
  if ($IncludeDetails) {
    Write-Host "  Tenant: $tenantId" -ForegroundColor Gray
  }
  Write-Host ""

  $subscriptionList += [PSCustomObject]@{
    name = $name
    id = $id
    state = $state
    tenantId = $tenantId
  }
}

# Output as JSON for consumption by other scripts
$subscriptionList | ConvertTo-Json | Out-String | Write-Host

Write-Host ""
Write-Host "Total subscriptions: $($subscriptionList.Count)" -ForegroundColor Green
