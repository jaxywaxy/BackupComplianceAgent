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
pwsh ./scripts/check-backup.ps1 `
  -SubscriptionId "<sub-id>" `
  -ResourceGroupName "<rg>"

### Generate remediation plan
pwsh ./scripts/generate-plan.ps1 `
  -SubscriptionId "<sub-id>" `
  -ResourceGroupName "<rg>"

### Apply backup
pwsh ./scripts/apply-backup.ps1 `
  -VaultName "<vault>" `
  -VaultRG "<rg>" `
  -VmName "<vm>" `
  -VmRG "<rg>"
