# Backup Remediation Plan

This document describes the backup remediation plan workflow and the newly added AVM (Azure Verified Module) for Recovery Services Vault deployment.

## Overview

The backup remediation plan process performs the following steps:

1. **Scan VMs** - Scans all virtual machines in a subscription
2. **Check Compliance** - Determines if each VM has backup enabled
3. **Evaluate Tags** - Checks for required owner and environment tags
4. **Generate Plan** - Creates a remediation plan with two types of actions:
   - **Vault Deployments** - Deploy missing Recovery Services Vaults using AVM
   - **Backup Enablement** - Enable backups on non-compliant VMs

## Configuration

### Backup Rules (`config/backup-rules.yaml`)

Defines which VMs require backups based on environment:

```yaml
backup_rules:
  default:
    required: true
    policy: default

  prod:
    required: true
    policy: daily-35d

  nonprod:
    required: true
    policy: daily-14d
```

### Vault Mapping (`config/vault-mapping.yaml`)

Maps subscriptions to existing Recovery Services Vaults:

```yaml
vaults:
  - subscription_id: "<your-sub-id>"
    resource_group: "rg-backup-shared"
    vault_name: "rsv-backup-aue-001"
    default_policy: "DefaultPolicy"
```

### Vault Deployment (`config/vault-deployment.yaml`)

Configures the AVM deployment of new Recovery Services Vaults:

```yaml
vault_deployment:
  shared_resource_group: 'rg-backup-shared'
  vaults:
    - name_template: 'rsv-backup-{region}-001'
      regions:
        - australiaeast
        - australiasoutheast
```

## Workflow

### 1. Generate Remediation Plan

**Trigger:** Manual workflow dispatch or automated schedule

```bash
pwsh ./scripts/generate-plan.ps1 -SubscriptionId "<sub-id>"
```

**Output:**
- `output/plans/remediation.json` - Machine-readable plan
- `output/plans/remediation.md` - Human-readable plan summary

**Plan Structure:**
```json
{
  "vaultDeployments": [
    {
      "vaultName": "rsv-backup-aue-001",
      "vaultRG": "rg-backup-shared",
      "location": "australiaeast"
    }
  ],
  "plan": [
    {
      "vmName": "vm-prod-001",
      "vaultName": "rsv-backup-aue-001",
      "action": "EnableBackup",
      "policyName": "daily-35d"
    }
  ],
  "notifications": [
    {
      "level": "Warning",
      "message": "Missing owner tag"
    }
  ]
}
```

### 2. Review Plan

The plan is automatically committed to a new branch and a PR is created for review. Review:
- Vault deployments needed
- VMs scheduled for backup enablement
- Any notifications or warnings

### 3. Apply Remediation

**Trigger:** Merge the remediation PR to main

The apply workflow automatically:

1. **Deploys missing vaults** using AVM bicep templates
   - Creates shared resource group if needed
   - Deploys vault with soft delete enabled
   - Waits for vault to be ready

2. **Enables backups** on VMs
   - Assigns backup policies
   - Configures retention settings

## Scripts

### `generate-plan.ps1`

Scans subscription and generates remediation plan.

**Parameters:**
- `SubscriptionId` (required) - Azure subscription ID
- `ResourceGroupName` (optional) - Specific RG to scan

**Logic:**
1. Lists all VMs in subscription
2. Checks for existing backups
3. Validates required tags (owner, environment)
4. Evaluates backup requirements based on environment
5. Detects missing vaults and adds deployment items
6. Generates JSON and markdown outputs

### `deploy-vault.ps1`

Deploys a Recovery Services Vault using AVM bicep template.

**Parameters:**
- `SubscriptionId` (required) - Azure subscription ID
- `ResourceGroupName` (required) - RG for vault
- `VaultName` (required) - Name of the vault
- `Location` (optional) - Azure region (default: australiaeast)

**Logic:**
1. Creates resource group if needed
2. Deploys vault using bicep template
3. Configures soft delete protection
4. Waits for vault to be ready

### `apply-backup.ps1`

Enables backup for a specific VM.

**Parameters:**
- `VaultName` (required) - Name of the vault
- `VaultRG` (required) - Vault resource group
- `VmName` (required) - VM name
- `VmRG` (required) - VM resource group
- `PolicyName` (optional) - Backup policy name

## Vault Naming Convention

When creating new vaults automatically, the following naming convention is used:

```
rsv-backup-{region-code}-{sequence}
```

Example: `rsv-backup-aue-001` for australiaeast

All vaults are deployed to the shared resource group defined in `vault-deployment.yaml`.

## Features

### Automatic Vault Discovery

- Scans existing vaults in the subscription
- Prefers vaults in the same region as VMs
- Falls back to mapped vaults if available

### Automatic Vault Deployment

- Detects when no suitable vault exists
- Generates deployment plan item
- Deploys vault on remediation apply using AVM

### Soft Delete Protection

- Automatically enabled on all deployed vaults
- Prevents accidental vault deletion
- Configurable via bicep parameters

### Failure Handling

- Validates all required tags before planning
- Checks policy availability
- Handles missing vaults gracefully
- Continues processing on partial failures

## Best Practices

1. **Tag All VMs** - Ensure all VMs have owner and environment tags
2. **Configure Vault Mapping** - Map subscriptions to existing vaults when available
3. **Review Plans** - Always review generated plans before merging
4. **Monitor Deployments** - Check logs for any deployment issues
5. **Test in Non-Prod** - Test workflow in non-production environments first

## Troubleshooting

### Plan shows no items

- Check if all VMs have required tags
- Verify backup-rules configuration
- Ensure Azure CLI is authenticated

### Vault deployment fails

- Verify resource group doesn't already exist (if creating)
- Check bicep template syntax in `infra/main.bicep`
- Ensure subscription has sufficient quota
- Review Azure CLI error messages

### Backup enablement fails

- Verify vault exists and is accessible
- Check if backup policy exists in vault
- Ensure VM and vault are in same region (recommended)
- Check VM backup prerequisites met

## Infrastructure as Code

The vault deployment uses Azure Bicep template: `infra/main.bicep`

**Parameters:**
- `location` - Azure region (default: australiaeast)
- `vaultName` - Name of the vault
- `skuName` - SKU type (default: Standard)
- `enableSoftDelete` - Enable soft delete (default: true)

**Output:**
- `vaultId` - Resource ID of created vault
- `vaultName` - Name of created vault
- `vaultLocation` - Location of created vault
