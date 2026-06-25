# Quick Start Guide - Backup Remediation Plan

## One-Time Setup

### 1. Configure Your Subscription

Edit `config/vault-mapping.yaml`:
```yaml
vaults:
  - subscription_id: "your-subscription-id-here"
    resource_group: "rg-backup-shared"
    vault_name: "rsv-backup-aue-001"
    default_policy: "DefaultPolicy"
```

### 2. Configure Backup Rules

Edit `config/backup-rules.yaml` to match your requirements:
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

### 3. Set GitHub Secrets & Variables

In GitHub repository settings:
- **Secrets:**
  - `AZURE_CLIENT_ID` - Service principal client ID
  - `AZURE_TENANT_ID` - Azure tenant ID

- **Variables:**
  - `SUBSCRIPTION_ID` - Azure subscription ID

### 4. Ensure VMs Have Tags

All VMs must have:
- `owner` tag - Contact person for the VM
- `environment` tag - prod, nonprod, dev, stage, etc.

```bash
az vm update -g rg-myresourcegroup -n myvm --set tags.owner="user@example.com" tags.environment="prod"
```

## Running the Remediation Workflow

### Step 1: Generate Plan (Manual Trigger)

1. Go to **GitHub Actions** → **Generate Remediation Plan**
2. Click **Run workflow**
3. Enter:
   - Subscription ID (required)
   - Resource Group (optional - leave blank for all RGs)
4. Workflow runs and creates a PR

### Step 2: Review Plan

1. Check the generated PR
2. Review `output/plans/remediation.md` for details
3. Look for:
   - Vaults that need deployment
   - VMs scheduled for backup
   - Any warnings or notifications
4. Approve or request changes

### Step 3: Apply Changes

1. **Merge** the PR to `main`
2. **Apply Remediation** workflow runs automatically
3. Workflow will:
   - Deploy missing vaults
   - Enable backups on VMs
   - Log completion status

### Step 4: Verify

```bash
# Check vaults were created
az backup vault list --subscription $SUBSCRIPTION_ID

# Check VM backup status
az backup item list --vault-name rsv-backup-aue-001 --resource-group rg-backup-shared
```

## Common Commands

### Generate plan for specific resource group
```bash
./scripts/generate-plan.ps1 -SubscriptionId "sub-id" -ResourceGroupName "rg-mygroup"
```

### Deploy vault manually
```bash
./scripts/deploy-vault.ps1 `
  -SubscriptionId "sub-id" `
  -ResourceGroupName "rg-backup-shared" `
  -VaultName "rsv-backup-aue-001" `
  -Location "australiaeast"
```

### Enable backup on VM manually
```bash
./scripts/apply-backup.ps1 `
  -VaultName "rsv-backup-aue-001" `
  -VaultRG "rg-backup-shared" `
  -VmName "myvm" `
  -VmRG "myrg" `
  -PolicyName "daily-35d"
```

## Troubleshooting

### No plan items generated
**Check:**
- Are VMs missing tags? Add owner and environment tags
- Are vaults already deployed? Use `az backup vault list`
- Are backups already enabled? Check vault for protected items

### Vault deployment fails
**Check:**
- Resource group already exists? Yes → OK, will use it
- Bicep template is valid? Run `bicep build infra/main.bicep`
- Subscription has quota? Check Azure limits

### Backup enablement fails
**Check:**
- Vault exists? Run `az backup vault list`
- Vault has policies? Run `az backup policy list --vault-name <name> --resource-group <rg>`
- VM meets backup requirements? Check prerequisites in Azure docs

### Policy not found
**Check:**
- Policy name in backup-rules.yaml matches vault? Verify with `az backup policy list`
- Update backup-rules.yaml with correct policy names
- Or let system auto-select first available policy

## Understanding the Plan

### Vault Deployments Section
```
## Vault Deployments Required
- **Vault:** rsv-backup-aue-001
  - Resource Group: rg-backup-shared
  - Location: australiaeast
  - Triggered by VM: vm-prod-001
```
→ Indicates a vault will be created

### Remediation Items Section
```
- **VM:** vm-prod-001
  - Resource Group: rg-workload
  - Vault: rsv-backup-aue-001 (rg-backup-shared)
  - Policy: daily-35d
  - Environment: prod
  - Owner: user@example.com
```
→ VM will have backup enabled with specified policy

### Notifications Section
```
- **Warning**: Missing owner tag
  - VM: vm-dev-001
  - Resource Group: rg-development
```
→ VM will be skipped, needs manual intervention

## Best Practices

1. **Tag everything** - Ensure all VMs have owner and environment tags
2. **Test first** - Run in non-prod subscription first
3. **Review plans** - Always review generated plans before applying
4. **Monitor logs** - Check GitHub Actions logs for any warnings
5. **Keep configs updated** - Update vault-mapping.yaml as infrastructure changes
6. **Schedule regularly** - Consider running plan generation on a schedule
7. **Document exceptions** - Track any VMs that skip backup and why

## Workflow Summary

```
Weekly/Monthly Trigger
        ↓
Generate Plan
  ├→ Scan VMs
  ├→ Check compliance
  ├→ Detect missing vaults
  └→ Create PR with plan
        ↓
Review Plan
  └→ Approve PR
        ↓
Apply Remediation
  ├→ Deploy vaults (if needed)
  └→ Enable backups on VMs
        ↓
Monitor & Verify
  └→ Check vault status
```

## Next Steps

1. [Configure your subscription](REMEDIATION_PLAN.md#configuration)
2. [Run generate plan workflow](#running-the-remediation-workflow)
3. [Review the plan](REMEDIATION_PLAN.md#workflow)
4. [Understand troubleshooting](REMEDIATION_PLAN.md#troubleshooting)
5. [Read full documentation](REMEDIATION_PLAN.md)

## Support

For issues:
1. Check [Troubleshooting section](REMEDIATION_PLAN.md#troubleshooting)
2. Review GitHub Actions logs
3. Verify Azure CLI commands work manually
4. Check Azure subscription permissions
