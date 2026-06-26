# Backup Remediation Plan

Generated: 2026-06-26 13:20:28Z

## Summary
- Vault deployments required: 0
- Total plan items: 3
- Total notifications: 1

## Remediation Items
- **VM:** vm-dev-002
  - Resource Group: RG-DEV
  - Vault: rsv-backup-aus-001 (rg-backup-shared)
  - Policy: HourlyLogBackup
  - Environment: dev
  - Owner: jacqui.rennie@slingshot.co.nz
  - Decision: EnableBackup

- **VM:** vm-prod-001
  - Resource Group: RG-PROD
  - Vault: rsv-backup-aus-001 (rg-backup-shared)
  - Policy: HourlyLogBackup
  - Environment: prod
  - Owner: jacqui.rennie@slingshot.co.nz
  - Decision: EnableBackup

- **VM:** vm-prod-002
  - Resource Group: RG-PROD
  - Vault: rsv-backup-aus-001 (rg-backup-shared)
  - Policy: HourlyLogBackup
  - Environment: prod
  - Owner: jacqui.rennie@slingshot.co.nz
  - Decision: EnableBackup

## Notifications
- **Warning**: Missing owner tag.
  - VM: vm-dev-001
  - Resource Group: RG-DEV

