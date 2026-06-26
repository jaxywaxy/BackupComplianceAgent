# GitHub Setup Guide for Backup Remediation

## Required Configuration

### 1. Repository Variables

Go to: **Settings → Secrets and variables → Variables**

Click **New repository variable** and add these variables:

| Variable Name | Value | Example |
|---|---|---|
| `SUBSCRIPTION_ID` | Your Azure subscription ID | `594e0bd0-2a8d-4419-b281-87869c20fd03` |

**Screenshot path:** Settings → Secrets and variables → Variables → New repository variable

### 2. Repository Secrets

Go to: **Settings → Secrets and variables → Secrets**

Click **New repository secret** and add these secrets:

| Secret Name | Value | Where to find |
|---|---|---|
| `AZURE_CLIENT_ID` | Service principal client ID | Azure Portal → App registrations → Your app → Application (client) ID |
| `AZURE_TENANT_ID` | Azure tenant ID | Azure Portal → Azure Active Directory → Directory ID |

**Screenshot path:** Settings → Secrets and variables → Secrets → New repository secret

## How to Get Azure Credentials

### Option 1: Use Existing Service Principal

If you already have a service principal with Azure CLI:

```bash
# Get your current context
az account show

# Get tenant ID
az account show --query tenantId -o tsv

# Get subscription ID
az account show --query id -o tsv

# Get service principal details (if using one)
az ad sp list --display-name "your-app-name" --query "[0].appId" -o tsv
```

### Option 2: Create New Service Principal

```bash
# Create a new service principal
az ad sp create-for-rbac --name "BackupComplianceAgent" \
  --role "Contributor" \
  --scopes "/subscriptions/594e0bd0-2a8d-4419-b281-87869c20fd03"

# Output will show:
# "appId": <AZURE_CLIENT_ID>
# "tenant": <AZURE_TENANT_ID>
```

## Verification

### Check Variables are Set

1. Go to **Settings → Secrets and variables → Variables**
2. You should see `SUBSCRIPTION_ID` listed
3. Click it to verify the value

### Check Secrets are Set

1. Go to **Settings → Secrets and variables → Secrets**
2. You should see `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` listed
3. Secrets are masked (you can't see the values, but they're there)

## Testing the Workflow

1. Commit the remediation plan:
   ```bash
   git add output/plans/remediation.json
   git commit -m "Generated backup remediation plan"
   git push origin main
   ```

2. Go to **GitHub Actions → Apply Backup Remediation**

3. Click **Run workflow → Run workflow**

4. Watch the run - it should:
   - ✓ Verify SUBSCRIPTION_ID is set
   - ✓ Find remediation plan
   - ✓ Deploy vault
   - ✓ Enable backups on VMs

5. Check the workflow logs for details

## Troubleshooting

### "SUBSCRIPTION_ID variable not set"
- Go to Settings → Secrets and variables → Variables
- Add the `SUBSCRIPTION_ID` variable with your subscription ID

### "Azure Login failed"
- Check `AZURE_CLIENT_ID` and `AZURE_TENANT_ID` are set in Secrets
- Verify the service principal has permissions on the subscription
- Ensure the service principal has the "Contributor" role

### "No remediation plan found"
- Run the "Generate Remediation Plan" workflow first
- Merge the PR to push remediation.json to main
- Then run "Apply Backup Remediation"

### "Failed to deploy vault"
- Check Azure permissions
- Check if vault name is unique
- Check resource group doesn't already exist with conflicting configuration

## Complete Example

Here's what you should have:

**Settings → Secrets and variables → Variables:**
```
SUBSCRIPTION_ID = 594e0bd0-2a8d-4419-b281-87869c20fd03
```

**Settings → Secrets and variables → Secrets:**
```
AZURE_CLIENT_ID = (masked value like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
AZURE_TENANT_ID = (masked value like xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)
```

Once these are set correctly, the workflows will work!
