# Backup Compliance Agent (PoC)

## Purpose
Detect and optionally remediate Azure VM backup compliance
without using Azure Policy.

## Central Governance Pattern

This repository is a central compliance agent for subscription-level backup governance.
It scans VMs, evaluates compliance using tags, generates remediation plans, and publishes results through GitHub workflows.

## Features (v1)
- Subscription-wide backup compliance scanning
- Tag-driven evaluation for `owner` and `environment`
- Actionable remediation plan generation
- GitHub PR creation only when a real remediation plan exists
- Human-reviewed backup enablement after plan approval

## What it contains
- `scripts/check-backup.ps1` — scan VMs and backup configuration
- `scripts/generate-plan.ps1` — generate remediation plans and markdown
- `scripts/apply-backup.ps1` — apply backup protection to a VM
- `config/backup-rules.yaml` — compliance rule definitions
- `config/vault-mapping.yaml` — vault selection and mapping logic
- `.github/workflows/compliance-scan.yml` — scan workflow with GitHub summary
- `.github/workflows/remediationplan.yml` — remediation plan workflow with PR creation
- `.github/workflows/validate.yml` — repo validation for scripts, YAML, and Bicep

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

## Outputs
- `output/reports/compliance.json`
- `output/plans/remediation.json`
- `output/plans/remediation.md`

## GitHub workflow behavior
- `compliance-scan.yml` publishes a scan summary in the run summary and uploads `output/reports/` as artifacts.
- `remediationplan.yml` commits generated plan artifacts and creates a PR only when there are actionable backup remediation items.
- `validate.yml` checks scripting, YAML, and Bicep quality before changes are merged.

## Notes
- `check-backup.ps1` writes `output/reports/compliance.json`.
- `generate-plan.ps1` writes `output/plans/remediation.json` and `output/plans/remediation.md`.
- Workflows can run at subscription scope or optionally target a single resource group.
