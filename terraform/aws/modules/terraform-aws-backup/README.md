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
COMPLIANCE lock with a **30-day minimum** on both vaults. PITR and automated
restore testing remain off. Set `vault_lock_mode = "GOVERNANCE"` explicitly to
defer COMPLIANCE; production does not require that mode.

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

The final generated names are validated separately. Without name overrides,
the effective prefix limits are 40 characters for the snapshot selection,
29 for PITR, 47 for the DR vault, and 37 for the restore testing plan.
Restore selection limits also depend on the resource type suffix.

For a long existing prefix, set only the names that exceed their limit:

```hcl
default_selection_name    = "payments-snapshot"
continuous_selection_name = "payments-continuous"
dr_vault_name             = "payments-backup-dr"
restore_testing_plan_name = "payments_restore_test"
restore_testing_selection_names = {
  DynamoDB = "payments_dynamodb"
}
```

These inputs are optional; existing valid names do not change. No name is
silently truncated. Preserve deployed names: changing an override can replace
the corresponding resource. Review the consumer plan before applying.

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

`resource_types = ["Aurora"]` expands to `arn:aws:rds:*:*:cluster:*`.
This is an RDS cluster ARN pattern, not an Aurora engine filter; it can also
match DocumentDB or Neptune clusters, subject to AWS Backup service opt-in.
For Aurora-only scope, use known Aurora cluster ARNs without the broad type
selector or additional OR tags:

```hcl
resource_types = []
selection_tags = {}
resource_arns = [
  "arn:aws:rds:eu-south-1:123456789012:cluster:payments-aurora"
]
```

Alternatively, use only a dedicated tag applied to the intended Aurora
clusters. Verify the selected inventory in the workload account. A tag does
not narrow an existing type-wide wildcard because selectors use OR.

The module rejects more than 30 selection tags, more than 500 distinct ARNs
in an inclusion or exclusion list, and more than 30 wildcard ARNs in either
list. Type-derived patterns count toward the inclusion limit. Backup start
windows must be at least 60 whole minutes; completion windows must be positive
whole minutes. Additional rules and presets use the same checks.

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
| Lock mode | COMPLIANCE, overridable to GOVERNANCE | GOVERNANCE, overridable to COMPLIANCE |
| Default minimum | Fixed 30 days on primary and DR vaults | Fixed 7 days |
| Maximum retention | 3650 days | 3650 days |
| PITR and cold storage | Explicit opt-in | Explicit opt-in |

Dev and UAT both use `environment = "nonprod"`. Adding a shorter snapshot, copy,
or PITR rule never lowers the default minimum automatically. Incompatible
retention fails validation. An explicit `vault_lock_min_retention_days` overrides
the default for both vaults. Every managed retention must fit the relevant
minimum and `vault_lock_max_retention_days`.

Retention must be positive whole days. Cold transition must be non-negative
whole days, with zero disabling it. A transition after 30 days requires at least
120 days of retention: 30 warm days plus 90 days after transition. Copy lifecycle
must also satisfy this rule and the destination lock bounds.

**GOVERNANCE is not permanent immutability:** sufficiently privileged users can
remove its lock. **COMPLIANCE becomes irreversible after its cooling-off period**
in either environment. Production defaults to COMPLIANCE with a three-day
cooling-off period, but callers may explicitly select GOVERNANCE.

**Upgrade warning:** an existing production caller that leaves `vault_lock_mode`
unset will now plan COMPLIANCE. To defer that transition, set
`vault_lock_mode = "GOVERNANCE"` before upgrading. Review existing lock settings
and a consumer plan before applying; finalized COMPLIANCE settings cannot be
changed or rolled back by reverting the module version.

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

Every preset accepts optional `plan_name` and `selection_name` inputs. Defaults
remain unchanged. The final selection name must fit 50 characters. Without
overrides, the maximum `vault_name` length is 28 for hourly, 23 for weekly-full,
20 for long-retention, and 26 for archival. For example, preserve a long vault
name and pass `selection_name = "payments-weekly-selection"` to weekly-full
instead of renaming the vault.

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

When testing is enabled, `restore_testing_resource_types` must not be empty.
Allowed types are Aurora, DocumentDB, DynamoDB, EBS, EC2, EFS, FSx, Neptune,
RDS, Redshift, and S3. Regional availability and service prerequisites remain
caller-owned. `restore_testing_start_window` must be a whole number of hours
expressed in minutes, from 60 to 10080. The validation duration must be a whole
number of hours from 1 to 168.

Use `restore_testing_metadata_overrides` to replace AWS-inferred settings for
a selected resource type, for example when RDS must use an existing subnet
group and security groups rather than the default VPC:

```hcl
enable_restore_testing         = true
restore_testing_resource_types = ["RDS"]
restore_testing_metadata_overrides = {
  RDS = {
    DBSubnetGroupName   = "restore-test-subnets"
    VpcSecurityGroupIds = jsonencode(["sg-0123456789abcdef0"])
  }
}
```

Override values are strings and apply only to that type's selection. Replace
the example identifiers with caller-owned resources. Unspecified types retain
AWS-inferred settings. Keys must match selected resource types; metadata keys
and values must be valid for the service and environment. The module does not
create a VPC, subnet group, security group, or additional IAM permissions.
See [AWS restore metadata](https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-testing-inferred-metadata.html).

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
| `default_selection_name`, `continuous_selection_name`, `dr_vault_name` | Optional name overrides; existing valid defaults are preserved |
| `selection_tags`, `resource_types`, `resource_arns` | At least one inclusion selector is required |
| `excluded_resource_arns` | Exclude resources from the default selection |
| `retention_days`, `copy_retention_days` | Primary snapshot and copy retention |
| `enable_continuous_backup` | Opt into a separate continuous plan |
| `continuous_backup_selection_tags`, `continuous_retention_days` | Dedicated PITR scope and independent 1-35-day retention |
| `cold_storage_after` | Optional snapshot cold transition; service-specific support required |
| `vault_lock_mode` | COMPLIANCE default in prod; GOVERNANCE in nonprod; either may be explicitly selected |
| `vault_lock_min_retention_days`, `vault_lock_max_retention_days` | Explicit lock bounds; maximum defaults to 3650 |
| `vault_lock_changeable_for_days` | COMPLIANCE cooling-off period; default three days |
| `default_plan_additional_rules` | Extra schedules on the default selection |
| `enable_restore_testing` | Opt into automated restore testing |
| `restore_testing_plan_name`, `restore_testing_selection_names` | Optional plan name and selection names keyed by selected resource type |
| `restore_testing_metadata_overrides` | Service-specific restore metadata maps keyed by selected resource type |
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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.72.0, < 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.72.0, < 6.0.0 |
| <a name="provider_aws.dr"></a> [aws.dr](#provider\_aws.dr) | >= 5.72.0, < 6.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_continuous_plan"></a> [continuous\_plan](#module\_continuous\_plan) | ./modules/backup-plan | n/a |
| <a name="module_default_plan"></a> [default\_plan](#module\_default\_plan) | ./modules/backup-plan | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_backup_restore_testing_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_restore_testing_plan) | resource |
| [aws_backup_restore_testing_selection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_restore_testing_selection) | resource |
| [aws_backup_vault.dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault) | resource |
| [aws_backup_vault_lock_configuration.dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_lock_configuration) | resource |
| [aws_backup_vault_lock_configuration.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/backup_vault_lock_configuration) | resource |
| [aws_iam_role.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.restore](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.restore_kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.backup_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.backup_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.restore_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.restore_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_alias.backup_dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key.backup_dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_kms_key_policy.backup](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_kms_key_policy.backup_dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_caller_identity.dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.kms_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.kms_policy_dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.dr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_region.primary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | Primary region where the workload lives. Must match the caller-supplied aws provider. | `string` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment type. Drives default behaviour for Vault Lock, cross-region copy, retention, etc. | `string` | n/a | yes |
| <a name="input_backup_schedule"></a> [backup\_schedule](#input\_backup\_schedule) | Cron expression for the backup schedule. | `string` | `"cron(0 1 * * ? *)"` | no |
| <a name="input_backup_window_minutes"></a> [backup\_window\_minutes](#input\_backup\_window\_minutes) | Duration of the backup window in minutes. | `number` | `480` | no |
| <a name="input_cold_storage_after"></a> [cold\_storage\_after](#input\_cold\_storage\_after) | Number of days before transitioning recovery points to cold storage. 0 (default) disables the transition. When set, retention\_days must be at least cold\_storage\_after + 90 (AWS Backup requirement). | `number` | `null` | no |
| <a name="input_continuous_backup_selection_tags"></a> [continuous\_backup\_selection\_tags](#input\_continuous\_backup\_selection\_tags) | Dedicated, non-empty tags required when continuous backup is enabled.<br/>Continuous backup always uses its own selection; it never falls back to<br/>snapshot tags. Tag matches use OR, so each tag must identify only supported<br/>S3 or RDS/Aurora resources. DynamoDB PITR is separate native configuration. | `map(string)` | `null` | no |
| <a name="input_continuous_retention_days"></a> [continuous\_retention\_days](#input\_continuous\_retention\_days) | Independent AWS Backup PITR retention in whole days, from 1 to 35. | `number` | `35` | no |
| <a name="input_continuous_selection_name"></a> [continuous\_selection\_name](#input\_continuous\_selection\_name) | Explicit PITR selection name. Defaults to <solution\_prefix>-continuous-selection; the final name must fit the AWS 50-character limit. | `string` | `null` | no |
| <a name="input_copy_retention_days"></a> [copy\_retention\_days](#input\_copy\_retention\_days) | Retention period for cross-region copies. Defaults to the primary retention\_days. | `number` | `null` | no |
| <a name="input_cross_region_copy"></a> [cross\_region\_copy](#input\_cross\_region\_copy) | Deprecated compatibility input. The module no longer uses this variable to<br/>decide whether DR copy is enabled.<br/><br/>Current behaviour:<br/>  - prod    : DR copy is enabled by default and requires dr\_region<br/>  - nonprod : DR copy is disabled | `string` | `"Default"` | no |
| <a name="input_default_plan_additional_rules"></a> [default\_plan\_additional\_rules](#input\_default\_plan\_additional\_rules) | Optional scheduled rules appended to the default backup plan. Use this<br/>when the same selection of resources needs extra schedules or retention<br/>policies without creating a separate backup-plan module.<br/><br/>These rules reuse the core module's primary vault, default selection, and<br/>backup IAM role. For separate selections or fully custom plans, use the<br/>backup-plan sub-module or one of the preset wrappers instead. | <pre>list(object({<br/>    rule_name               = string<br/>    schedule                = string<br/>    start_window            = optional(number)<br/>    completion_window       = optional(number)<br/>    cold_storage_after      = optional(number, 0)<br/>    delete_after            = number<br/>    recovery_point_tags     = optional(map(string), {})<br/>    copy_to_dr              = optional(bool)<br/>    copy_cold_storage_after = optional(number)<br/>    copy_delete_after       = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_dr_region"></a> [dr\_region](#input\_dr\_region) | Target region for production DR copy. Must differ from aws\_region, match the caller's aws.dr provider, and belong to the existing EU allow-list. | `string` | `null` | no |
| <a name="input_default_selection_name"></a> [default\_selection\_name](#input\_default\_selection\_name) | Explicit snapshot selection name. Defaults to <solution\_prefix>-selection; the final name must fit the AWS 50-character limit. Changing an existing name may replace the selection. | `string` | `null` | no |
| <a name="input_dr_vault_name"></a> [dr\_vault\_name](#input\_dr\_vault\_name) | Explicit DR vault name. Defaults to <solution\_prefix>-dr. Changing an existing name replaces the vault. | `string` | `null` | no |
| <a name="input_enable_continuous_backup"></a> [enable\_continuous\_backup](#input\_enable\_continuous\_backup) | Enable dedicated AWS Backup continuous backup for supported S3 and RDS/Aurora resources. Disabled by default. DynamoDB PITR is configured natively by the caller. | `bool` | `null` | no |
| <a name="input_enable_restore_testing"></a> [enable\_restore\_testing](#input\_enable\_restore\_testing) | Whether to create a Restore Testing Plan. | `bool` | `false` | no |
| <a name="input_excluded_resource_arns"></a> [excluded\_resource\_arns](#input\_excluded\_resource\_arns) | Optional list of resource ARNs (or wildcard ARNs) to exclude from the default plan selection. Useful to drop ephemeral resources when selecting by service type. | `list(string)` | `[]` | no |
| <a name="input_kms_deletion_window_in_days"></a> [kms\_deletion\_window\_in\_days](#input\_kms\_deletion\_window\_in\_days) | Waiting period in days before KMS key deletion. Between 7 and 30. | `number` | `30` | no |
| <a name="input_kms_enable_key_rotation"></a> [kms\_enable\_key\_rotation](#input\_kms\_enable\_key\_rotation) | Enable automatic annual key rotation. | `bool` | `true` | no |
| <a name="input_kms_multi_region"></a> [kms\_multi\_region](#input\_kms\_multi\_region) | Whether the backup CMKs are multi-region keys. Multi-region keys simplify cross-region DR restore (the same key material exists in the DR region). Cannot be changed after key creation. See decision §6.3 (KMS key protection). | `bool` | `false` | no |
| <a name="input_resource_arns"></a> [resource\_arns](#input\_resource\_arns) | Optional list of explicit (or wildcard) resource ARNs to select, combined with resource\_types and selection\_tags. | `list(string)` | `[]` | no |
| <a name="input_resource_types"></a> [resource\_types](#input\_resource\_types) | Optional list of AWS service types to back up by selecting ALL of their<br/>resources via wildcard ARNs (e.g. ["DynamoDB", "S3", "RDS"]), as an<br/>alternative or complement to tag-based selection.<br/><br/>Supported types are defined by the resource\_type\_arns map in the backup-plan<br/>sub-module (currently: S3, DynamoDB, EC2, EBS, RDS, Aurora, EFS). Unsupported<br/>values are rejected with a clear error at plan time.<br/>Note: AWS Backup allows at most 30 wildcard ARNs per selection. | `list(string)` | `[]` | no |
| <a name="input_restore_testing_max_duration"></a> [restore\_testing\_max\_duration](#input\_restore\_testing\_max\_duration) | Hours a restored test resource is retained so optional validation can run (validation\_window\_hours). Between 1 and 168. | `number` | `24` | no |
| <a name="input_restore_testing_metadata_overrides"></a> [restore\_testing\_metadata\_overrides](#input\_restore\_testing\_metadata\_overrides) | Restore metadata string maps keyed by selected resource type, for example RDS = { DBSubnetGroupName = "restore-subnets" }. Values replace AWS-inferred metadata only for that selection. Encode structured values with jsonencode when required by AWS. | `map(map(string))` | `{}` | no |
| <a name="input_restore_testing_plan_name"></a> [restore\_testing\_plan\_name](#input\_restore\_testing\_plan\_name) | Explicit restore testing plan name. Defaults to <solution\_prefix with hyphens replaced by underscores>\_restore\_test. Names must use 1-50 letters, digits or underscores. | `string` | `null` | no |
| <a name="input_restore_testing_resource_types"></a> [restore\_testing\_resource\_types](#input\_restore\_testing\_resource\_types) | Protected resource types to include in the Restore Testing Plan selections (e.g., DynamoDB, EBS, RDS, S3, EFS, Redshift). One selection is created per type. | `list(string)` | <pre>[<br/>  "DynamoDB",<br/>  "EBS",<br/>  "RDS",<br/>  "S3",<br/>  "EFS"<br/>]</pre> | no |
| <a name="input_restore_testing_schedule"></a> [restore\_testing\_schedule](#input\_restore\_testing\_schedule) | Cron expression for restore testing schedule. | `string` | `"cron(0 3 ? * SAT *)"` | no |
| <a name="input_restore_testing_selection_names"></a> [restore\_testing\_selection\_names](#input\_restore\_testing\_selection\_names) | Optional restore selection names keyed by protected resource type. Unspecified types retain <normalized solution\_prefix>\_<lowercase type>. Names must use 1-50 letters, digits or underscores. | `map(string)` | `{}` | no |
| <a name="input_restore_testing_start_window"></a> [restore\_testing\_start\_window](#input\_restore\_testing\_start\_window) | Start window for restore testing in minutes. | `number` | `480` | no |
| <a name="input_retention_days"></a> [retention\_days](#input\_retention\_days) | Number of days to retain recovery points. Defaults to 35 in prod and 14 in nonprod. Must be >= the Vault Lock minimum retention. | `number` | `null` | no |
| <a name="input_selection_tags"></a> [selection\_tags](#input\_selection\_tags) | Map of tag key/value pairs used to select resources for the backup plan (default selection method, decision §8). Optional if resource\_types or resource\_arns are set. | `map(string)` | `{}` | no |
| <a name="input_solution_prefix"></a> [solution\_prefix](#input\_solution\_prefix) | Prefix for resources created by this solution (vault, IAM roles, KMS aliases, plans). Caution: changing this value may break execution as different AWS resources have different naming limits (e.g. no underscore for IAM roles). | `string` | `"backup-solution"` | no |
| <a name="input_tag_identifier_prefix"></a> [tag\_identifier\_prefix](#input\_tag\_identifier\_prefix) | Prefix for the Name tag applied to resources created by this solution. Defaults to solution\_prefix. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags to apply to all resources created by the module. | `map(string)` | `{}` | no |
| <a name="input_vault_lock_changeable_for_days"></a> [vault\_lock\_changeable\_for\_days](#input\_vault\_lock\_changeable\_for\_days) | Cooling-off period in days during which the Vault Lock can still be removed (Compliance mode only). Minimum 3. | `number` | `3` | no |
| <a name="input_vault_lock_max_retention_days"></a> [vault\_lock\_max\_retention\_days](#input\_vault\_lock\_max\_retention\_days) | Maximum retention in days enforced by Vault Lock. Recovery points cannot have a retention longer than this. Backup jobs targeting the vault must set delete\_after within [vault\_lock\_min\_retention\_days, vault\_lock\_max\_retention\_days]; jobs outside this range are rejected by the vault. | `number` | `3650` | no |
| <a name="input_vault_lock_min_retention_days"></a> [vault\_lock\_min\_retention\_days](#input\_vault\_lock\_min\_retention\_days) | Explicit minimum retention for both vaults. When null, the fixed minimum is 30 days in prod and 7 in nonprod; shorter plan retention never lowers it automatically. External plans remain caller-owned. | `number` | `null` | no |
| <a name="input_vault_lock_mode"></a> [vault\_lock\_mode](#input\_vault\_lock\_mode) | Vault Lock mode: defaults to COMPLIANCE in prod and GOVERNANCE in nonprod. Either mode may be explicitly selected in either environment. COMPLIANCE becomes immutable after its cooling-off period. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_backup_plan_arn"></a> [backup\_plan\_arn](#output\_backup\_plan\_arn) | ARN of the default backup plan. |
| <a name="output_backup_plan_id"></a> [backup\_plan\_id](#output\_backup\_plan\_id) | ID of the default backup plan. |
| <a name="output_backup_role_arn"></a> [backup\_role\_arn](#output\_backup\_role\_arn) | ARN of the IAM role used by AWS Backup for backup operations. |
| <a name="output_continuous_plan_id"></a> [continuous\_plan\_id](#output\_continuous\_plan\_id) | ID of the dedicated continuous-backup plan. Null unless enable\_continuous\_backup is true with non-empty dedicated tags. |
| <a name="output_dr_kms_key_arn"></a> [dr\_kms\_key\_arn](#output\_dr\_kms\_key\_arn) | ARN of the KMS key encrypting the DR vault. Null if cross-region copy is disabled. |
| <a name="output_dr_kms_key_id"></a> [dr\_kms\_key\_id](#output\_dr\_kms\_key\_id) | ID of the KMS key encrypting the DR vault. Null if cross-region copy is disabled. Pass to the alerting module to monitor the DR key for deletion. |
| <a name="output_dr_vault_arn"></a> [dr\_vault\_arn](#output\_dr\_vault\_arn) | ARN of the DR backup vault. Null if cross-region copy is disabled. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key encrypting the primary vault. |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | ID of the KMS key encrypting the primary vault. |
| <a name="output_restore_role_arn"></a> [restore\_role\_arn](#output\_restore\_role\_arn) | ARN of the IAM role used by AWS Backup for restore operations. |
| <a name="output_restore_testing_plan_arn"></a> [restore\_testing\_plan\_arn](#output\_restore\_testing\_plan\_arn) | ARN of the Restore Testing Plan. Null if restore testing is disabled. |
| <a name="output_vault_arn"></a> [vault\_arn](#output\_vault\_arn) | ARN of the primary backup vault. |
| <a name="output_vault_name"></a> [vault\_name](#output\_vault\_name) | Name of the primary backup vault. |
<!-- END_TF_DOCS -->