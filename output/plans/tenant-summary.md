# Tenant-Level Backup Compliance Report

**Generated:** 2026-06-26 03:09:39

## Executive Summary

| Metric | Count |
|--------|-------|
| Subscriptions Scanned | 2 |
| Total Non-Compliant VMs | 3 |
| Vault Deployments Needed | 1 |
| Notifications | 2 |

## Subscription Details

### sub-az-landingzone

**ID:** 57aa2cb5-1f26-4f7c-ae52-918da1394d09

| Metric | Count |
|--------|-------|
| VMs Needing Backup |  |
| Vault Deployments |  |
| Notifications |  |

---

### sub-lz-bicep

**ID:** 594e0bd0-2a8d-4419-b281-87869c20fd03

| Metric | Count |
|--------|-------|
| VMs Needing Backup |  |
| Vault Deployments |  |
| Notifications |  |

**VMs to Protect:**

- **vm-dev-002** (Owner: jacqui.rennie@slingshot.co.nz)
  - Environment: dev
  - Vault: rsv-backup-aus-001
  - Policy: 

- **vm-prod-001** (Owner: jacqui.rennie@slingshot.co.nz)
  - Environment: prod
  - Vault: rsv-backup-aus-001
  - Policy: 

- **vm-prod-002** (Owner: jacqui.rennie@slingshot.co.nz)
  - Environment: prod
  - Vault: rsv-backup-aus-001
  - Policy: 

---

## Next Steps

1. Review the detailed plan in tenant-plan.json

2. For each subscription, create a remediation PR

3. Approve and merge PRs to apply remediation

4. Monitor backup jobs in Azure Portal

