# Tenant-Level and Multi-Subscription Setup

## Current State
- ✅ Works at **subscription level** - scans single subscription
- ✅ Generates remediation plan per subscription
- ✅ Applies backups at subscription level

## Proposed Enhancements

### Option 1: Tenant-Level Scanning (Recommended)

Create a master workflow that:
1. Discovers all subscriptions in the tenant
2. Runs scan/plan for each subscription
3. Aggregates results
4. Reports across tenant

**Files to create/modify:**
- `scripts/get-all-subscriptions.ps1` - List all subscriptions user has access to
- `scripts/generate-tenant-plan.ps1` - Wrapper that generates plans for all subscriptions
- `.github/workflows/tenant-compliance-scan.yml` - Scan all subscriptions

### Option 2: Subscription-Level with Centralized Config

Enhance existing system to:
1. Support multiple subscriptions in config
2. Map vaults across subscriptions
3. Run scans in parallel

**Files to create/modify:**
- `config/subscriptions.yaml` - Define subscriptions and their mappings
- `scripts/generate-plan.ps1` - Add optional tenant-level mode
- `.github/workflows/generate-plan.yml` - Add input for subscription selection

## Implementation

### Step 1: Create Tenant-Level Plan Script

```powershell
# scripts/generate-tenant-plan.ps1
param(
  [string]$TenantId,
  [string[]]$SubscriptionIds,  # Optional filter
  [switch]$IncludeOnlyCompliant
)

# Get all subscriptions (or filtered list)
# For each subscription:
#   - Run generate-plan.ps1
#   - Aggregate results
# Output:
#   - tenant-plan.json (all subscriptions)
#   - tenant-summary.md
```

### Step 2: Update Configuration

Create `config/subscriptions.yaml`:
```yaml
subscriptions:
  - id: "594e0bd0-2a8d-4419-b281-87869c20fd03"
    name: "sub-lz-bicep"
    environment: "production"
    vault-rg: "rg-backup-shared"
    
  - id: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    name: "sub-staging"
    environment: "staging"
    vault-rg: "rg-backup-shared-stage"
```

### Step 3: Create Tenant Workflow

`.github/workflows/tenant-compliance-scan.yml`:
```yaml
name: Tenant Compliance Scan

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly
  workflow_dispatch:
    inputs:
      scan-type:
        description: 'Scan all or specific subscription'
        required: true
        default: 'all'
        type: choice
        options:
          - all
          - specific

jobs:
  scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Scan all subscriptions
        run: pwsh ./scripts/generate-tenant-plan.ps1
```

## Benefits

✅ **Tenant-level visibility** - See compliance across all subscriptions
✅ **Scalability** - Add/remove subscriptions easily
✅ **Centralized management** - Single configuration for all subscriptions
✅ **Parallel processing** - Scan multiple subscriptions concurrently
✅ **Aggregated reporting** - Combined dashboard and reports
✅ **Flexible** - Run at tenant or subscription level as needed

## Rollout Plan

**Phase 1** (Current):
- ✅ Single subscription scanning
- ✅ Manual workflow dispatch per subscription

**Phase 2** (Recommended):
- Add `get-all-subscriptions.ps1` script
- Create `generate-tenant-plan.ps1` wrapper
- Add tenant-level workflow

**Phase 3** (Future):
- Multi-tenant support
- Cross-tenant reporting
- Policy governance at tenant level

## Example: Tenant-Level Scan

Once implemented:

```bash
# Scan all subscriptions in tenant
pwsh ./scripts/generate-tenant-plan.ps1

# Scan specific subscriptions
pwsh ./scripts/generate-tenant-plan.ps1 `
  -SubscriptionIds @("sub-1", "sub-2", "sub-3")

# View tenant report
cat ./output/plans/tenant-plan.json | jq '.summary'
```

## Questions to Answer

1. Do you want to scan **all** subscriptions in the tenant, or only **specified** ones?
2. Should policies be managed **per-subscription** or **tenant-wide**?
3. Do you need **different backup policies** per subscription/environment?
4. Should remediation be **automated** or require **manual approval** at tenant level?

## Next Steps

Would you like me to:
1. ✅ Create the tenant-level scanning scripts?
2. ✅ Update configuration to support multiple subscriptions?
3. ✅ Create the tenant workflow?
4. ✅ Do all three?
