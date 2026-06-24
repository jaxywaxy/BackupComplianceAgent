# Backup Compliance Agent

Automated backup compliance verification and remediation for Azure resources.

## Overview

This agent monitors backup compliance across Azure subscriptions and automatically applies remediation actions to ensure all resources meet organizational backup requirements.

## Quick Start

See [ARCHITECTURE.md](ARCHITECTURE.md) for system design and [scripts/](scripts/) for usage examples.

## Configuration

- [backup-rules.yaml](config/backup-rules.yaml) - Define backup compliance rules
- [vault-mapping.yaml](config/vault-mapping.yaml) - Map resources to Recovery Services vaults

## Infrastructure

Azure infrastructure is defined in [infra/main.bicep](infra/main.bicep).

## Output

Generated reports and plans are stored in [output/](output/).
