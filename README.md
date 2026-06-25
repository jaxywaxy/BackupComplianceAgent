# Backup Compliance Agent (PoC)

## Purpose
Detect and optionally remediate Azure VM backup compliance
without using Azure Policy.

## Features (v1)
- Detect VMs without backup
- Generate remediation plan
- Apply backup policy (manual approval)

## Usage

### Check compliance
Subscription-wide:
```powershell
pwsh ./scripts/check-backup.ps1 `
  -SubscriptionId "<sub-id>"
```

Resource group only:
```powershell
pwsh ./scripts/check-backup.ps1 `
  -SubscriptionId "<sub-id>" `
  -ResourceGroupName "<rg>"
```

### Generate remediation plan
Subscription-wide:
```powershell
pwsh ./scripts/generate-plan.ps1 `
  -SubscriptionId "<sub-id>"
```

Resource group only:
```powershell
pwsh ./scripts/generate-plan.ps1 `
  -SubscriptionId "<sub-id>" `
  -ResourceGroupName "<rg>"
```

### Apply backup
pwsh ./scripts/apply-backup.ps1 `
  -VaultName "<vault>" `
  -VaultRG "<rg>" `
  -VmName "<vm>" `
  -VmRG "<rg>"

### Notes
- `check-backup.ps1` now writes `output/reports/compliance.json`.
- `generate-plan.ps1` now writes `output/plans/remediation.json`.
- GitHub workflows accept `resourceGroupName` as optional. If omitted they scan the whole subscription.
