# Tenant-Level Backup Compliance Workflow

## Overview

The tenant-level scanning system allows you to:
- ✅ Scan all subscriptions in your Azure tenant automatically
- ✅ Generate compliance reports across subscriptions
- ✅ Identify non-compliant VMs organization-wide
- ✅ Plan vault deployments and backups at scale

## Getting Started

### 1. Run Local Discovery

Discover all subscriptions you have access to:

```bash
pwsh ./scripts/get-all-subscriptions.ps1
```

This shows all subscriptions and their IDs. You'll use these IDs in the tenant plan.

### 2. Generate Tenant Plan Locally

Scan all subscriptions and generate a comprehensive plan:

```bash
pwsh ./scripts/generate-tenant-plan.ps1 -AllSubscriptions
```

Or scan specific subscriptions:

```bash
pwsh ./scripts/generate-tenant-plan.ps1 `
  -SubscriptionIds @("sub-id-1", "sub-id-2", "sub-id-3")
```

### 3. Review Results

Check the generated reports:

```bash
# Summary report (markdown)
cat ./output/plans/tenant-summary.md

# Detailed plan (JSON)
cat ./output/plans/tenant-plan.json | jq '.'
```

## GitHub Actions Workflow

### Automatic Tenant Scan (Weekly)

The `tenant-scan.yml` workflow runs automatically every Sunday at 2 AM UTC.

**To view results:**
1. Go to **GitHub → Actions → Tenant Compliance Scan**
2. Click the latest run
3. Check the **Step Summary** for the report
4. Download artifacts for detailed JSON report

### Manual Tenant Scan

Run on-demand:

1. Go to **GitHub → Actions → Tenant Compliance Scan**
2. Click **Run workflow**
3. Choose:
   - **all** - Scan all subscriptions
   - **specific** - Scan only listed subscriptions
4. If "specific", enter subscription IDs (comma-separated)
5. Click **Run workflow**

## Understanding the Tenant Plan

### tenant-plan.json Structure

```json
{
  "generatedAt": "2026-06-26T10:30:00Z",
  "tenantId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "subscriptionCount": 3,
  "subscriptions": [
    {
      "subscriptionId": "sub-1-id",
      "subscriptionName": "sub-lz-bicep",
      "vaultDeployments": 1,
      "vmsNeedingBackup": 2,
      "notifications": 1,
      "plan": [...],
      "vaultDeployments": [...]
    }
  ],
  "summary": {
    "totalVMs": 6,
    "compliantVMs": 4,
    "nonCompliantVMs": 2,
    "vaultDeploymentsNeeded": 1,
    "notificationsCount": 1
  }
}
```

### tenant-summary.md Report

Markdown summary showing:
- Executive summary statistics
- Per-subscription breakdown
- VMs needing backup
- Actions needed

## Workflow: Tenant → Subscription

### Step 1: Run Tenant Scan

```bash
pwsh ./scripts/generate-tenant-plan.ps1 -AllSubscriptions
```

### Step 2: Review Tenant Plan

```bash
cat ./output/plans/tenant-summary.md
```

### Step 3: For Each Subscription with Issues

Generate subscription-level plan and create remediation PR:

```bash
# Generate plan for specific subscription
pwsh ./scripts/generate-plan.ps1 -SubscriptionId "subscription-id"

# Commit and push
git add output/plans/remediation.json
git commit -m "Generated backup remediation plan for subscription-xyz"
git push origin main
```

### Step 4: Apply Remediation

The GitHub workflow automatically:
1. Creates PR with remediation plan
2. On merge, deploys vaults and enables backups
3. Reports results back

## Scenarios

### Scenario 1: Weekly Organization Audit

**Goal:** Check all subscriptions every week

```bash
# GitHub automation handles this automatically
# Schedule: Every Sunday 2 AM UTC
# Results: Check Actions tab → Tenant Compliance Scan
```

### Scenario 2: Monthly Compliance Report

**Goal:** Generate a compliance report for all subscriptions

```bash
pwsh ./scripts/generate-tenant-plan.ps1 -AllSubscriptions

# Results saved to:
# - ./output/plans/tenant-plan.json
# - ./output/plans/tenant-summary.md

# Upload to SharePoint or email the summary
```

### Scenario 3: New Subscription Onboarding

**Goal:** Scan new subscription and enable backups

```bash
# Discover new subscription
pwsh ./scripts/get-all-subscriptions.ps1

# Generate plan for new subscription
pwsh ./scripts/generate-plan.ps1 -SubscriptionId "new-sub-id"

# Create remediation PR
git add output/plans/remediation.json
git commit -m "Onboard new subscription: new-sub-id"
git push origin main

# Merge PR to apply backups automatically
```

### Scenario 4: Audit Specific Subscriptions

**Goal:** Audit only production subscriptions

```bash
pwsh ./scripts/generate-tenant-plan.ps1 `
  -SubscriptionIds @("prod-sub-1", "prod-sub-2", "prod-sub-3")

# Review results
cat ./output/plans/tenant-summary.md
```

## Interpreting Results

### vaultDeploymentsNeeded

Number of new Recovery Services Vaults that need to be created.

- **High number** → Many subscriptions missing backup infrastructure
- **Action:** Deploy vaults automatically via remediation workflow

### vmsNeedingBackup

Number of VMs without backup protection.

- **High number** → Compliance issue
- **Action:** Generate remediation plans per subscription and approve

### notificationsCount

Number of issues preventing remediation (missing tags, etc.).

- **High number** → Data quality issues
- **Action:** Tag VMs with owner and environment

## Best Practices

✅ **Weekly Reviews** - Set calendar reminder for weekly scan results
✅ **Tagging Enforcement** - Ensure all VMs have owner/environment tags
✅ **Approval Process** - Review remediation PRs before merging
✅ **Audit Trail** - Keep plan artifacts for compliance history
✅ **Alerting** - Configure notifications for non-compliance

## Troubleshooting

### Scan shows all VMs non-compliant

**Possible causes:**
- VMs missing owner/environment tags
- Backup rules not configured correctly
- Subscription-level issues

**Action:**
1. Check backup-rules.yaml
2. Verify VM tags
3. Review subscription configuration

### Tenant plan not updating

**Possible causes:**
- GitHub Actions schedule not running
- No changes detected
- Workflow disabled

**Action:**
1. Manually trigger workflow
2. Check Actions tab for errors
3. Verify workflow file syntax

### Can't scan specific subscriptions

**Possible causes:**
- Wrong subscription ID format
- Insufficient permissions
- Subscription not in tenant

**Action:**
1. Verify IDs with `get-all-subscriptions.ps1`
2. Check Azure permissions
3. Ensure subscriptions are in tenant

## Next Steps

1. ✅ Commit tenant workflow files to repo
2. ✅ Verify GitHub Actions can run tenant-scan
3. ✅ Run first tenant scan and review results
4. ✅ Create subscription-level remediation plans
5. ✅ Apply backups at scale

Ready to scale! 🚀
