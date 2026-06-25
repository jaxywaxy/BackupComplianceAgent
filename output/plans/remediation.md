# Backup Remediation Plan

Generated: 2026-06-26 11:40:31Z

## Summary
- Vault deployments required: 1
- Total plan items: 3
- Total notifications: 1

## Vault Deployments Required
- **Vault:** rsv-backup-aus-001
  - Resource Group: rg-backup-shared
  - Location: australiaeast
  - Triggered by VM: vm-dev-002

## Remediation Items
- **VM:** vm-dev-002
  - Resource Group: RG-DEV
  - Vault: rsv-backup-aus-001 (rg-backup-shared)
  - Policy: 
  - Environment: dev
  - Owner: jacqui.rennie@slingshot.co.nz
  - Decision: EnableBackup

- **VM:** vm-prod-001
  - Resource Group: RG-PROD
  - Vault: rsv-backup-aus-001 (rg-backup-shared)
  - Policy: 
  - Environment: prod
  - Owner: jacqui.rennie@slingshot.co.nz
  - Decision: EnableBackup

- **VM:** vm-prod-002
  - Resource Group: RG-PROD
  - Vault: rsv-backup-aus-001 (rg-backup-shared)
  - Policy: 
  - Environment: prod
  - Owner: jacqui.rennie@slingshot.co.nz
  - Decision: EnableBackup

## Notifications
- **Warning**: Missing owner tag.
  - VM: vm-dev-001
  - Resource Group: RG-DEV

