# Architecture

## System Design

This document describes the overall architecture of the Backup Compliance Agent.

### Components

1. **Check Module** (`check-backup.ps1`)
   - Scans Azure resources for backup compliance status
   - Generates compliance reports

2. **Planning Module** (`generate-plan.ps1`)
   - Analyzes non-compliant resources
   - Creates remediation plans

3. **Apply Module** (`apply-backup.ps1`)
   - Executes remediation actions
   - Updates resource configurations

### Configuration

- **Backup Rules**: Define which resources must have backups
- **Vault Mapping**: Specify target Recovery Services vaults

### Infrastructure

Azure infrastructure deployed via Bicep templates in [infra/](infra/).

### Output

- **Reports**: Compliance status and audit logs
- **Plans**: Planned remediation actions
- **Audit**: Historical audit records
