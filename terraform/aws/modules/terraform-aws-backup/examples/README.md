# AWS Backup examples

Each example is a standalone root using relative repository module sources.
No private backend is configured. Production callers must supply their own
remote backend, credentials, provider mappings, and unique resource names.

| Example | Scope |
| --- | --- |
| [production](./production/) | GOVERNANCE, mandatory same-account DR, restore testing, compatible presets, and primary-region alerting. |
| [non-production](./non-production/) | GOVERNANCE, no DR or PITR, optional alerting, both aliases mapped to the primary provider. |
| [with-extra-plans](./with-extra-plans/) | Additional core rules, external presets, and bespoke plans; hourly retention explicitly fits the production vault. |
| [continuous-pitr](./continuous-pitr/) | Explicit dedicated AWS Backup PITR selection, independent 35-day PITR and 90-day snapshots. DynamoDB PITR is separate native configuration. |
| [by-service-type](./by-service-type/) | Intentional type-wide wildcard selection and exclusions; not an isolated workload-tag default. |
| [nonprod-compliance-optin](./nonprod-compliance-optin/) | Explicit irreversible COMPLIANCE after its cooling-off period; no DR. |

## Choose a starting point

Start with the minimal [non-production](../README.md#non-production-setup) or
[production](../README.md#production-setup) consumer configuration in the core
README. These example roots deliberately demonstrate extra policy options:

- `non-production` overrides daily retention to seven days and adds a weekly
  120-day rule plus alerts. Core's non-production default is 14 days.
- `production` uses 365-day daily retention, cold transition after 90 days,
  an additional primary-only rule, restore testing, presets, and alerts.
  Core's production default is 35 days without cold storage or restore testing.
- `continuous-pitr` uses 90-day snapshots and a separate 35-day PITR plan.
  The two plans have different selectors. A resource intended for both must
  match both tag maps; only compatible resources should match the PITR tags.
- `nonprod-compliance-optin` is not an ordinary development setup. It explicitly
  chooses COMPLIANCE, 35-day retention and minimum, and a seven-day cooling-off
  period. COMPLIANCE becomes irreversible after that period even in non-prod.

`solution_prefix` names the backup installation; `selection_tags` selects
existing workload resources. Neither core nor these examples applies selection
tags to the workload for you. Multiple tag entries match with OR, not AND.
See [names and selection](../README.md#names-and-resource-selection) and
[snapshots versus PITR](../README.md#scheduled-snapshots-versus-continuous-pitr).

Cold-storage examples require a compatible service; do not apply their cold
settings to S3 or continuous backups. Relative sources are for running these
roots in a repository checkout, not for copying the root unchanged into another
repository. External consumers should use the documented immutable Git sources.

## Validation

CI runs all examples through `make terraform-backup-check` from the repository
root: backend-disabled initialization, validation, and native tests with every
AWS provider mocked. Authored examples and tests are unverified until the
candidate CI run succeeds. No local initialization occurs during this work.

The [core README](../README.md) documents Git subdirectory distribution and the
proposed, unpublished `aws-backup-v1.0.0` release. Relative sources make these
examples independent of release availability.

## Operational boundaries

Mock success is not evidence that a backup, DR copy, data-checked restore, or
notification works in AWS. S3 requires versioning, appropriate IAM policies,
and EventBridge for continuous backup. Advanced DynamoDB snapshots and native
DynamoDB PITR are separate protections. Confirm service/region support before
an authorized sandbox rollout.

An alerting module in the same root shares state with backup. DR monitoring
requires separate provider-mapped composition. Confirm SNS email subscriptions.
Do not perform casual cleanup: KMS `prevent_destroy` remains intact and a
finalized COMPLIANCE lock cannot be undone by changing a module ref.
