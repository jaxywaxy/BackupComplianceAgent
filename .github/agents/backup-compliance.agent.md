# Backup Compliance Agent Definition

## Purpose

Automated backup compliance verification and remediation for Azure resources.

## Responsibilities

- Monitor backup compliance across Azure subscriptions
- Generate compliance reports and audit logs
- Create remediation plans for non-compliant resources
- Execute automated remediation actions
- Maintain audit trail of all compliance changes

## Inputs

- Azure subscription and resource group filters
- Backup compliance rules configuration
- Recovery Services vault mappings

## Outputs

- Compliance reports (reports/)
- Remediation plans (plans/)
- Audit logs (audit/)

## Trigger

- Scheduled compliance checks
- On-demand verification requests
- Resource creation/modification events
