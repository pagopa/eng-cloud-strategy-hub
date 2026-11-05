# terraform-aws-backup

Reusable AWS Backup modules for workload teams. Each core module instance creates
its own encrypted vaults, Vault Lock configuration, backup and restore IAM roles,
and a scheduled snapshot plan. Continuous backup and automated restore testing
are optional.

This is a shared module library, not a central account collecting all backups.
Consumers deploy it in their own workload accounts. Notifications use the
separate [alerting module](../terraform-aws-backup-alerting/).

## Contents

- [Before you start](#before-you-start)
- [Non-production setup](#non-production-setup)
- [Production setup](#production-setup)
- [Names and resource selection](#names-and-resource-selection)
- [Scheduled snapshots versus continuous PITR](#scheduled-snapshots-versus-continuous-pitr)
- [Retention and Vault Lock](#retention-and-vault-lock)
- [Additional schedules and presets](#additional-schedules-and-presets)
- [Alerts and restore testing](#alerts-and-restore-testing)
- [Inputs and outputs](#inputs-and-outputs)
- [Validation and rollout](#validation-and-rollout)

## Before you start

Use a Git subdirectory source; do not copy module files into consumer repositories.
Replace `<COMMIT_SHA>` in every snippet with the same published immutable commit
that has passed the required CI checks. The proposed `aws-backup-v1.0.0` release
is not yet published or verified. Snippets are templates until their ref is
replaced; none is evidence of a successful deployment.

The consumer owns:

- AWS credentials and any assume-role configuration.
- Provider configurations and a remote backend with state locking.
- Separate deployment/state boundaries for production and non-production.
- Workload resources, their selection tags, and service-specific prerequisites.
- Region/service availability, AWS Backup service opt-in where required, and
  permissions for the workload's backup and restore operations.
- Retention requirements, notification recipients, and real recovery tests.

Declare the following in each consumer root:

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.72.0, < 6.0.0"
    }
  }
}
```

Core requires AWS provider 5.72.0 because Terraform needs restore-testing schemas
even when those resources are disabled. Native mock tests require Terraform
1.7 or later; the deployment compatibility floor remains 1.5.0.

## Non-production setup

Use this in the non-production root. Both module aliases map to the primary
provider because this environment creates no DR resources.

```hcl
provider "aws" {
  region = "eu-south-1"
}

module "backup" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup?ref=<COMMIT_SHA>"

  providers = {
    aws    = aws
    aws.dr = aws
  }

  aws_region      = "eu-south-1"
  environment     = "nonprod"
  solution_prefix = "payments-dev-eu-south-1"

  selection_tags = {
    "backup-workload" = "payments-dev"
  }

  tags = {
    Environment = "dev"
    Product     = "payments"
  }
}
```

This configures daily snapshots retained for **14 days**, one encrypted primary
vault, GOVERNANCE lock, no DR copy, no PITR, and no automated restore testing.
Set `retention_days = 7` inside the module call if a seven-day policy is intended.
Invoking the module creates the backup infrastructure; `nonprod` is not an
additional enable/disable switch.

The [non-production example](./examples/non-production/) deliberately overrides
snapshot retention to seven days and adds a weekly rule and alerting. Those are
example choices, not environment defaults.

## Production setup

Use this in a separate production root. Configure both providers for the same
AWS account, with different regions.

```hcl
provider "aws" {
  region = "eu-south-1"
}

provider "aws" {
  alias  = "dr"
  region = "eu-central-1"
}

module "backup" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup?ref=<COMMIT_SHA>"

  providers = {
    aws    = aws
    aws.dr = aws.dr
  }

  aws_region      = "eu-south-1"
  dr_region       = "eu-central-1"
  environment     = "prod"
  solution_prefix = "payments-prod-eu-south-1"

  selection_tags = {
    "backup-workload" = "payments-prod"
  }

  tags = {
    Environment = "prod"
    Product     = "payments"
  }
}
```

This configures daily snapshots retained for **35 days**, primary and DR
encrypted vaults, copies of the daily snapshots retained for **35 days**, and
GOVERNANCE lock on both vaults. PITR and automated restore testing remain off.

Production DR is mandatory. The deprecated `cross_region_copy` input does not
disable it. `dr_region` must match `aws.dr`, differ from `aws_region`, and be one
of `eu-central-1`, `eu-south-1`, `eu-west-1`, or `eu-west-3`. The module checks
the observed regions and that both providers use the same account.

For longer primary history with shorter DR retention, add:

```hcl
retention_days      = 90
copy_retention_days = 35
```

The [production example](./examples/production/) is an extended configuration
with longer retention, cold storage, restore testing, presets, and alerts.
Do not treat all of its options as mandatory or appropriate for every service.

## Names and resource selection

### `solution_prefix`: name the backup installation

This value names the infrastructure created by the module: vaults, IAM roles,
KMS aliases, and plans. For example:

```hcl
solution_prefix = "payments-prod-eu-south-1"
```

Choose a stable, unique value for each workload, environment, and regional
installation in the same account. IAM role names are account-global, not
region-local. Use 2-50 characters: letters, digits, hyphens, or underscores.
Changing the prefix after deployment may replace resources or conflict with
destruction protections. It does not select which workload resources to back up.

### `selection_tags`: choose existing workload resources

This map describes tags AWS Backup must match on the workload resources:

```hcl
selection_tags = {
  "backup-workload" = "payments-prod"
}
```

The consumer must apply the matching tag to each intended resource, through that
resource's own Terraform configuration:

```hcl
tags = {
  "backup-workload" = "payments-prod"
}
```

The module does **not** add this tag to workload resources. Its separate `tags`
input labels the infrastructure it creates; it does not choose backup targets.
Matching tags establish selection, not proof that a backup job succeeds.

Multiple `selection_tags` entries use legacy AWS `ListOfTags` **OR** semantics.
For example, `{ workload = "payments", stage = "prod" }` selects a resource
matching either tag, not only resources matching both. Prefer one workload and
environment-specific selection tag when isolation is required.

### Other selectors

| Input | Meaning |
| --- | --- |
| `resource_types` | All resources matching the module's service ARN patterns. Supported types: S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS. |
| `resource_arns` | Explicit resource ARNs or intentional wildcard patterns. |
| `excluded_resource_arns` | Exclusions mapped to AWS `NotResources`; not a standalone inclusion selector. |

Supply at least one inclusion selector. Tags, types, and ARNs combine as a
union, not an intersection. Type-wide selection can include unrelated workloads;
use it deliberately. See [by-service-type](./examples/by-service-type/) and the
[backup-plan module](./modules/backup-plan/) for selector details.

## Scheduled snapshots versus continuous PITR

**Scheduled backup** creates recovery points on a schedule. You restore to one
of the available recovery points. A daily backup does not contain changes made
after that recovery point.

**PITR means Point-In-Time Recovery.** Continuous backup maintains a recoverable
history, using service-specific mechanisms, so you can choose a time within its
available recovery window. It is not instantaneous replication or an immediate
restore; freshness, precision, and recovery duration depend on the service.

Example: a successful daily recovery point is available at 01:00, and data is
deleted accidentally at 15:00. The snapshot can recover the earlier state, but
not the intervening changes. PITR may recover the state at 14:59 if that time is
available. Neither mechanism guarantees that restored application data is valid;
test recovery separately.

| Property | Scheduled snapshots | AWS Backup continuous PITR |
| --- | --- | --- |
| Restore point | An available scheduled recovery point | A time within the available recovery window |
| Typical purpose | Historical recovery and long-term retention | Precise recovery from recent mistakes |
| Retention input | `retention_days` | `continuous_retention_days`, independently set to 1-35 days |
| Selection input | `selection_tags`, types, or ARNs | Required non-empty `continuous_backup_selection_tags` |
| Enabled by default | Yes, when core is invoked | No, in either environment |
| Cold storage | Only for supported services and valid lifecycle | Not supported |
| DR in this module | Daily snapshots copied in production; additional rules control their copies | The dedicated continuous plan has no copy actions |

They are complementary. A resource intended for both protections should match
both selections. Configuring a PITR tag alone does not enable PITR, and enabling
PITR never falls back to the snapshot selection.

Add these inputs inside either environment's `module "backup"` call:

```hcl
retention_days            = 90
enable_continuous_backup  = true
continuous_retention_days = 35

continuous_backup_selection_tags = {
  "backup-pitr" = "payments-prod"
}
```

Use an environment-specific PITR value, such as `payments-dev`, in non-production.
Apply that tag only to compatible S3 or supported RDS/Aurora resources. The
module cannot inspect tagged resources to prove their PITR compatibility.

- S3 requires versioning and appropriate backup/restore IAM permissions.
  Continuous S3 backup also requires EventBridge. S3 cold storage is unsupported.
- Native DynamoDB PITR is separate caller-owned table configuration. Advanced
  DynamoDB AWS Backup snapshots/copy features do not make DynamoDB a supported
  target for this continuous rule.
- Do not assume that copying a recovery point preserves destination PITR.
  This module's dedicated PITR plan does not configure DR copies.

See the [continuous-pitr example](./examples/continuous-pitr/), which uses
90-day snapshots and 35-day PITR without cold storage. Official references:
[continuous backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html),
[S3 backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/s3-backups.html),
and [advanced DynamoDB backup](https://docs.aws.amazon.com/aws-backup/latest/devguide/advanced-ddb-backup.html).

## Retention and Vault Lock

Retention is how long a recovery point is kept. Vault Lock limits the permitted
retention of jobs writing to that vault; its minimum is not the backup schedule
or the retention of every backup.

| Default | Production | Non-production |
| --- | --- | --- |
| Snapshot retention | 35 days | 14 days |
| Snapshot copy retention | Same as primary retention unless overridden | No copy |
| Lock mode | GOVERNANCE | GOVERNANCE |
| Automatic minimum | Lower of 35 days and the shortest core-managed retention in that vault | Lower of 7 days and the shortest core-managed retention |
| Maximum retention | 3650 days | 3650 days |
| PITR and cold storage | Explicit opt-in | Explicit opt-in |

The primary minimum includes primary snapshot rules and enabled PITR retention.
DR has its own derived minimum based only on actual copied rules. An explicit
`vault_lock_min_retention_days` applies to both vaults. Every managed retention
must fit the relevant minimum and `vault_lock_max_retention_days`.

Retention must be positive whole days. Cold transition must be non-negative
whole days, with zero disabling it. A transition after 30 days requires at least
120 days of retention: 30 warm days plus 90 days after transition. Copy lifecycle
must also satisfy this rule and the destination lock bounds.

**GOVERNANCE is not permanent immutability:** sufficiently privileged users can
remove its lock. **COMPLIANCE becomes irreversible after its cooling-off period**
in either environment. It is not enabled just because `environment = "prod"`.

The [nonprod-compliance-optin example](./examples/nonprod-compliance-optin/)
explicitly chooses COMPLIANCE, 35-day retention, a 35-day lock minimum, and a
seven-day cooling-off period. Those are deliberate policy choices, not a normal
development setup. Changing a module ref cannot undo a finalized COMPLIANCE lock.

Vault CMKs retain `prevent_destroy = true`. Do not remove it for routine cleanup
or to make tests pass. Key deletion requires a separately authorized recovery
and key-retention decision.

## Additional schedules and presets

Use `default_plan_additional_rules` for more schedules on the default selection,
primary vault, and backup role. Rule names must be unique. In production, rules
copy to DR by default; use `copy_to_dr = false` for a primary-only rule. Do not
set copy lifecycle fields on a rule that does not copy.

Use a separate preset or [backup-plan](./modules/backup-plan/) call when the
selection differs or a bespoke plan is needed:

| Preset | Default purpose and retention |
| --- | --- |
| [hourly-backup](./modules/presets/hourly-backup/) | Hourly schedule, seven-day retention |
| [weekly-full](./modules/presets/weekly-full/) | Weekly schedule, 90-day retention; the name does not guarantee job success or a service-specific full backup |
| [long-retention](./modules/presets/long-retention/) | 3650-day retention, cold transition after 90 days where supported |
| [archival](./modules/presets/archival/) | 3650-day retention, cold transition after 30 days where supported |

Core cannot discover external plans or adjust its locks for them. The consumer
must fit every external rule and on-demand job within the vault's bounds.
For example, override the hourly preset's seven-day default when writing to a
production vault whose minimum is 35 days:

```hcl
module "hourly" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup/modules/presets/hourly-backup?ref=<COMMIT_SHA>"

  vault_name      = module.backup.vault_name
  backup_role_arn = module.backup.backup_role_arn
  selection_tags = { "backup-workload" = "payments-prod" }
  retention_days = 35
}
```

See [with-extra-plans](./examples/with-extra-plans/). A frequent schedule is not
proof of an achieved RPO; observe successful recovery points and test restores.

## Alerts and restore testing

The core does not create notification resources. Add the alerting module beside
it in either consumer root, using that environment's prefix and recipients:

```hcl
module "backup_alerting" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup-alerting?ref=<COMMIT_SHA>"

  providers = { aws = aws }

  solution_prefix = "payments-prod-eu-south-1"
  kms_key_ids     = [module.backup.kms_key_id]
  email_endpoints = ["oncall@example.com"]
}
```

SNS email subscriptions require confirmation. CloudTrail supplies the configured
KMS API events. Test real notification delivery; creating the subscription is
not delivery evidence.

Primary-region alerting does not monitor DR automatically. For production DR,
add another alerting instance with `providers = { aws = aws.dr }`, a distinct
prefix, and `kms_key_ids = [module.backup.dr_kms_key_id]`. Independent module APIs
do not imply independent state when composed in one root. See the
[alerting README](../terraform-aws-backup-alerting/README.md).

Set `enable_restore_testing = true` to request scheduled restore tests in the
primary vault. The default schedule is Saturday at 03:00 UTC. Selection supports
one tag via a protected-resource condition, or up to 30 explicit ARNs without tags. Multi-tag
OR, exclusions, mixed selectors, type-wide selection, and implicit all-resource
fallback are rejected rather than silently broadening or narrowing scope.

Restore job completion is not proof of application data integrity or RTO.
The consumer must supply service prerequisites and its own recovery validation.

## Inputs and outputs

The complete contract is in [variables.tf](./variables.tf) and
[outputs.tf](./outputs.tf). The main inputs are:

| Input | Purpose |
| --- | --- |
| `environment` | Required: `prod` or `nonprod`; controls defaults and DR resources |
| `aws_region`, `dr_region` | Observed provider regions must match; DR region is required in production |
| `solution_prefix` | Stable installation name; default `backup-solution`, but use a unique explicit value |
| `selection_tags`, `resource_types`, `resource_arns` | At least one inclusion selector is required |
| `excluded_resource_arns` | Exclude resources from the default selection |
| `retention_days`, `copy_retention_days` | Primary snapshot and copy retention |
| `enable_continuous_backup` | Opt into a separate continuous plan |
| `continuous_backup_selection_tags`, `continuous_retention_days` | Dedicated PITR scope and independent 1-35-day retention |
| `cold_storage_after` | Optional snapshot cold transition; service-specific support required |
| `vault_lock_mode` | GOVERNANCE default or explicit COMPLIANCE |
| `vault_lock_min_retention_days`, `vault_lock_max_retention_days` | Explicit lock bounds; maximum defaults to 3650 |
| `vault_lock_changeable_for_days` | COMPLIANCE cooling-off period; default three days |
| `default_plan_additional_rules` | Extra schedules on the default selection |
| `enable_restore_testing` | Opt into automated restore testing |
| `tags` | Labels created infrastructure, not workload selection |

| Output | Consumer use |
| --- | --- |
| `vault_name`, `vault_arn` | Primary vault for additional plans |
| `dr_vault_arn` | DR vault; null in non-production |
| `backup_plan_id`, `backup_plan_arn` | Default plan identification |
| `continuous_plan_id` | Separate PITR plan; null unless enabled with valid dedicated tags |
| `backup_role_arn`, `restore_role_arn` | Service roles for backup and restore |
| `kms_key_id`, `kms_key_arn` | Primary encryption key; pass ID to alerting |
| `dr_kms_key_id`, `dr_kms_key_arn` | DR encryption key; null in non-production |
| `restore_testing_plan_arn` | Restore-testing plan; null when disabled |

Caller-owned providers support `count` and `for_each` with distinct names. The
core and presets reuse the same [backup-plan implementation](./modules/backup-plan/).

## Validation and rollout

The repository's [Terraform Backup workflow](../../../../.github/workflows/terraform-backup.yml)
is designed to run formatting, backend-disabled initialization, caller-root
validation, and native mock tests for all seven public modules and seven examples.
It also checks failure propagation, AWS provider 5.72.0, Terraform 1.5.7
compatibility, and workflow linting. Mock tests use Terraform 1.14.3.

Candidate-bound native CI evidence is still pending. Local formatting or authored
tests do not establish native success. This implementation performs no local
initialization, real AWS apply, release publication, or required-check changes.

A consumer rollout should:

1. Pin a published candidate that has passed the required CI jobs.
2. Configure its own backend and authentication, and review the consumer plan.
3. Deploy to one authorized non-production workload first. Stop promotion if
   the selection is wrong or backup, restore, or alert delivery fails.
4. Verify a real backup, a restore with data checks, and actual notifications.
5. Promote to production and verify a real DR copy and recovery from it.

Use the consumer's approved Terraform pipeline for deployment. The repository's
mock workflow is not that deployment pipeline. On failure, stop promotion and
review changes; do not use blanket destruction as rollback for protected keys
or finalized COMPLIANCE vaults.
