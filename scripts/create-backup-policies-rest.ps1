param(
  [string]$SubscriptionId,
  [string]$VaultName,
  [string]$VaultRG
)

if ([string]::IsNullOrWhiteSpace($SubscriptionId) -or [string]::IsNullOrWhiteSpace($VaultName) -or [string]::IsNullOrWhiteSpace($VaultRG)) {
  throw "SubscriptionId, VaultName, and VaultRG are required."
}

Write-Host "Creating backup policies for vault: $VaultName" -ForegroundColor Cyan

# Get access token
$token = az account get-access-token --query accessToken -o tsv
if (-not $token) {
  throw "Failed to get access token. Ensure you are authenticated with Azure CLI."
}

$headers = @{
  "Authorization" = "Bearer $token"
  "Content-Type"  = "application/json"
}

$apiVersion = "2023-02-01"
$baseUri = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$VaultRG/providers/Microsoft.RecoveryServices/vaults/$VaultName"

# Define policies to create
$policies = @(
  @{
    name = "DefaultPolicy"
    retention = 30
    frequency = "Daily"
    backupTime = "02:00"
  },
  @{
    name = "EnhancedPolicy"
    retention = 30
    frequency = "Hourly"
    backupTime = "02:00"
    interval = 4
    duration = 12
  }
)

foreach ($policy in $policies) {
  Write-Host ""
  Write-Host "Creating policy: $($policy.name)" -ForegroundColor Yellow

  # Check if policy already exists
  $getUri = "$baseUri/backupPolicies/$($policy.name)?api-version=$apiVersion"

  try {
    $response = Invoke-WebRequest -Uri $getUri -Headers $headers -Method Get -ErrorAction SilentlyContinue
    if ($response.StatusCode -eq 200) {
      Write-Host "  ✓ Policy already exists" -ForegroundColor Green
      continue
    }
  } catch {
    # Policy doesn't exist, continue to create
  }

  # Build policy JSON based on type
  if ($policy.name -eq "DefaultPolicy") {
    $policyJson = @{
      location = "australiaeast"
      properties = @{
        backupManagementType = "AzureIaasVM"
        policyType = "V1"
        schedulePolicy = @{
          schedulePolicyType = "SimpleSchedulePolicy"
          scheduleRunFrequency = "Daily"
          scheduleRunTimes = @("2026-06-26T02:00:00Z")
          scheduleWeeklyFrequency = 0
        }
        retentionPolicy = @{
          retentionPolicyType = "LongTermRetentionPolicy"
          dailySchedule = @{
            retentionTimes = @("2026-06-26T02:00:00Z")
            retentionDuration = @{
              count = $policy.retention
              durationType = "Days"
            }
          }
        }
        instantRpRetentionRangeInDays = 2
        timeZone = "UTC"
      }
    }
  } else {
    # EnhancedPolicy for Trusted Launch VMs
    $policyJson = @{
      location = "australiaeast"
      properties = @{
        backupManagementType = "AzureIaasVM"
        policyType = "V2"
        schedulePolicy = @{
          schedulePolicyType = "SimpleSchedulePolicyV2"
          scheduleRunFrequency = "Hourly"
          scheduleRunTimes = @("2026-06-26T02:00:00Z")
          hourlySchedule = @{
            interval = $policy.interval
            scheduleWindowDuration = $policy.duration
            scheduleWindowStartTime = "2026-06-26T02:00:00Z"
          }
        }
        retentionPolicy = @{
          retentionPolicyType = "LongTermRetentionPolicy"
          dailySchedule = @{
            retentionTimes = @("2026-06-26T02:00:00Z")
            retentionDuration = @{
              count = $policy.retention
              durationType = "Days"
            }
          }
        }
        instantRpRetentionRangeInDays = 2
        timeZone = "UTC"
      }
    }
  }

  # Create policy via REST API
  $createUri = "$baseUri/backupPolicies/$($policy.name)?api-version=$apiVersion"
  $body = $policyJson | ConvertTo-Json -Depth 10

  try {
    $response = Invoke-WebRequest -Uri $createUri `
      -Headers $headers `
      -Method Put `
      -Body $body `
      -ContentType "application/json"

    if ($response.StatusCode -eq 200 -or $response.StatusCode -eq 201) {
      Write-Host "  ✓ Policy created successfully" -ForegroundColor Green
    } else {
      Write-Host "  ⚠️  Unexpected status: $($response.StatusCode)" -ForegroundColor Yellow
    }
  } catch {
    $errorResponse = $_.Exception.Response
    if ($errorResponse.StatusCode -eq 409) {
      # Conflict means it already exists
      Write-Host "  ✓ Policy already exists" -ForegroundColor Green
    } else {
      Write-Host "  ✗ Failed to create policy: $_" -ForegroundColor Red
      throw
    }
  }
}

Write-Host ""
Write-Host "✓ Policy creation complete" -ForegroundColor Green
