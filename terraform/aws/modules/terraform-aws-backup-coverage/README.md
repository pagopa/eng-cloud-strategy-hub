# terraform-aws-backup-coverage

Independent expected-resource snapshot coverage for one AWS account and primary
Region. The module discovers tagged workloads even when AWS Backup has never
protected them. It does not use backup-job history or `ListProtectedResources`
as the expected inventory.

**Readiness: prototype-unverified.** Native Terraform, packaging, Python runtime
tests, failure propagation, and compatibility must pass in CI for the exact
published candidate. Local formatting is not technical certification.

## Source layout

- `main.tf` owns infrastructure and configuration preconditions.
- `iam.tf` owns Lambda and Scheduler trust and permission policies.
- `locals.tf` owns policy validation, runtime configuration, and alarm definitions.
- `lambda/coverage.py` separates inventory discovery, snapshot lookup, incident
  updates, and scan orchestration. S3 and DynamoDB discovery have separate
  methods; notification decisions use a side-effect-free method with early
  returns. All snapshot queries finish before incident updates; notifications
  still precede delivery-state persistence.

This separation does not change resource addresses, public inputs or outputs,
incident records, or notification contracts.

## Usage

The caller owns its AWS provider, credentials, remote backend, SNS topic, and
topic CMK. Use a unique workload/environment/Region prefix (2-45 characters).
Replace `<COMMIT_SHA>` with a published immutable candidate that has passed CI.
The proposed `aws-backup-v1.0.0` tag is not published or verified.

```hcl
provider "aws" { region = "eu-south-1" }

module "coverage" {
  source = "git::https://github.com/pagopa/eng-cloud-strategy-hub.git//terraform/aws/modules/terraform-aws-backup-coverage?ref=<COMMIT_SHA>"
  providers = { aws = aws }

  solution_prefix        = "orders-prod-eu-south-1"
  expected_resource_tags = { backup-workload = "orders-prod" }
  resource_types         = ["DynamoDB", "S3"]
  sns_topic_arn          = "arn:aws:sns:eu-south-1:123456789012:orders-alerts"
  sns_kms_key_arn        = "arn:aws:kms:eu-south-1:123456789012:key/00000000-0000-0000-0000-000000000001"
  coverage_policy = {
    max_backup_age_seconds      = 86400
    freshness_tolerance_seconds = 3600
    initial_grace_seconds       = 86400
    reminder_interval_seconds   = 86400
    schedule                    = "rate(15 minutes)"
  }
}
```

Set `enabled = false` for complete disablement without tags, types, policy, topic,
or key inputs. Every resource output is then null. For automatic composition
with an owned topic, use the [alerting module](../terraform-aws-backup-alerting/).
Its `enable_backup_coverage` defaults to true and requires explicit inputs.
See [examples](./examples/) for standalone, integrated, and disabled calls.

## Inventory and freshness contract

- Supported discovery types are `DynamoDB` tables and `S3` general purpose
  buckets. Directory buckets and other types are not supported. This limit
  applies to this scanner, not the generic core backup selectors.
- S3 uses paginated regional `ListBuckets` and `GetBucketTagging` with the
  expected account owner. DynamoDB uses paginated `ListTables` and
  `ListTagsOfResource`. Untagged S3 buckets are excluded explicitly; denied
  discovery/tagging or malformed pagination fails the scan.
- Every expected tag key/value must match: **AND semantics**. Core's legacy
  `selection_tags` use **OR semantics**. Identical configured maps do not prove
  identical selected inventories or correct AWS Backup service opt-in.
- Do not put the full workload tag set on scanner infrastructure. Its incident
  table is explicitly excluded from its own discovery, including inherited
  provider tags.
- Each expected ARN is checked through paginated
  `ListRecoveryPointsByResource(ManagedByAWSBackupOnly=true)`. Missing recovery
  points remain missing coverage; they never remove a resource from inventory.
  `ResourceNotFoundException` from Backup for an independently discovered ARN
  is explicitly logged as missing Backup registration; permission and other
  errors still fail the scan.
- Only `COMPLETED` same-account, primary-region snapshots qualify. Continuous
  recovery-point IDs are excluded by their documented `continuous` prefix.
  Unsupported completed ARN shapes or missing/future timestamps fail explicitly.
  Other recovery-point states do not establish usable coverage.
- Freshness measures documented recovery-point **CreationDate**, never backup
  completion time. A snapshot is fresh at age <= maximum age + tolerance.
  This is recovery-point-age evidence, not exact per-object data RPO or proof of
  recoverability. Initial grace starts at first observation and applies only
  when no usable snapshot exists; an already stale snapshot alerts immediately.
- No PITR-window verification, DR-copy freshness, missing-tag governance, or
  application restore validation is implemented. Existing event alerts remain
  separate and cover their configured copy/restore failures.

Thresholds must be whole seconds. Maximum age and reminder interval must be
positive; grace and tolerance may be zero. Tolerance must be below maximum age.
Schedules use rate expressions with correct singular/plural minute or hour units,
from 10 minutes to 24 hours (for example `rate(15 minutes)` or `rate(1 hour)`).
Reminder interval must be at least one cadence. No schedule or threshold is
inferred from retention, a prefix, or backup jobs.
Serialized coverage configuration is limited to 3000 UTF-8 bytes to leave
headroom within Lambda's 4 KB environment limit.

## Incident state and delivery

The DynamoDB table retains first-seen, active-scope, incident, reason, and
last-delivered notification state. It uses on-demand capacity, encryption, PITR,
strongly consistent reads, and conditional writes. It has no automatic TTL:
removed-resource incident evidence remains until separately reviewed cleanup.

Notifications carry `event`, `resource_arn`, `reason`, `observed_at`, `scanner`,
and `scope`. Events are `opened`, `reminder`, `recovered`, and `scope_removed`.
The last event is a scope change, **not recovery**; the former incident is
retained. Re-entry starts a new first-seen/grace cycle. Complete discovery and
all freshness queries must finish before any incident or removal transition.

Reserved Lambda concurrency is exactly one. The table has one scanner writer;
do not share it between functions or modify its records externally. Conditional
conflicts fail rather than overwrite state. Scheduler and Lambda retries are
bounded to two retries and at most one cadence of event age.
The caller must have sufficient account concurrency quota for this reservation.
An active incident cannot be closed by initial grace: a fresh usable snapshot
must exist.

Publication happens before recording delivery. SNS errors leave the transition
pending for retry. Delivery is **at-least-once**, not exactly-once: SNS success
followed by failed state persistence can duplicate a message. SNS confirmation
and real delivery still require consumer evidence.

## Health, dependencies, and cost

The module creates one Scheduler group/schedule, one Python 3.12 Lambda, two IAM
roles, an incident-state table, a 30-day log group, and five CloudWatch alarms.
The archive provider builds the ZIP from the adjacent Python source; no
provisioner, provider download, or cloud operation is run by the module code.
Terraform/provider initialization remains a caller or CI operation.

Metrics use `AWSBackup/Coverage`, dimension `Scanner=<prefix>-backup-coverage`:
`ScanStart`, `ScanSuccess`, `ScanFailure`, `InventorySize`, and `EmptyInventory`.
`ScanSuccess` means a complete non-empty **scan**, not absence of incidents.
Empty inventory logs a diagnostic and emits `EmptyInventory=1`, with no success
heartbeat. Failures are logged and raised.

Alarms detect scan failure, two consecutive periods without scan success,
empty inventory, Lambda errors, and Lambda throttles. The first scan is expected
within one cadence; the missing-success alarm allows two cadence periods for
startup. Inventory growth or API throttling can exhaust the 300-second execution
budget: the health alarms expose this; no partial scan is considered complete.

Runtime Boto3 and its dependencies come from the managed Lambda runtime. No
partial SDK dependencies are packaged. The handler fails explicitly if the
runtime lacks regional paginated S3 `ListBuckets` support. This trades a
standalone Git-source package for AWS-managed SDK version updates; runtime
compatibility and sandbox checks remain required. Adjacent test dependencies
pin Boto3; that pin is not a claim about the managed production SDK version.

Required constraints: Terraform >=1.5.0, AWS >=5.72.0,<6.0.0, archive >=2.4.0,<3.0.0.
Native mock tests need Terraform >=1.7.0. CI tests the exact AWS/archive minima
with Terraform 1.5.7 and runs mocks on 1.14.3.

Costs include Lambda execution, Scheduler invocations, DynamoDB reads/writes and
PITR, logs, five alarms, SNS publication, and KMS requests. Enumeration reads all
supported account resources before matching tags; tags do not bound scan cost.
One cadence increase multiplies scan frequency, not backup frequency.

## Caller-owned policy obligations

This module never replaces external topic or key policies. The caller must:

1. Permit `execution_role_arn` to publish to the standard SNS topic and use its
   symmetric customer-managed key (`kms:GenerateDataKey*`, `kms:Decrypt`).
2. Allow `cloudwatch.amazonaws.com` to publish to the topic and use that key.
   Scope service grants to the account and
   `arn:<partition>:cloudwatch:<region>:<account>:alarm:<prefix>-backup-coverage-*`.
3. Avoid explicit denies that invalidate the scanner's account-scoped inventory
   or regional Backup metadata permissions. No workload object reads or backup
   mutation permissions are granted.
4. Keep recipients confirmed and test delivery.

The integrated alerting module adds the publisher/alarm grants only to policies
it owns or an existing topic policy it was explicitly authorized to replace.
Both coverage messages and health alarms share SNS/CMK delivery. A failure of
that channel is a residual dependency, not solved by alarms on the same topic.

## Validation

CI runs:

```sh
terraform -chdir=terraform/aws/modules/terraform-aws-backup-coverage init -backend=false
terraform -chdir=terraform/aws/modules/terraform-aws-backup-coverage validate
terraform -chdir=terraform/aws/modules/terraform-aws-backup-coverage test
python3 -m pip install -r terraform/aws/modules/terraform-aws-backup-coverage/tests/requirements.txt
python3 -m unittest discover -s terraform/aws/modules/terraform-aws-backup-coverage/tests -p 'test_*.py'
make terraform-backup-check
```

Unit tests use controlled time and stubbed clients, without AWS credentials or
network calls. Native tests use mocked AWS providers and the real local archive
provider. Mock IAM structure is not effective authorization evidence. Do not
claim native CI, live backup/restore, or human delivery success from this source.

## Outputs

| Output | Enabled value |
| --- | --- |
| `lambda_function_arn` | Scanner function ARN |
| `execution_role_arn` | Lambda publisher role ARN |
| `incident_table_arn` | Incident-state table ARN |
| `schedule_arn` | Scheduler schedule ARN |
| `health_alarm_arns` | Map of five health alarm ARNs |

Every output above is null when disabled.

## Official references

- [S3 ListBuckets](https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListBuckets.html)
  and [bucket tags](https://docs.aws.amazon.com/AmazonS3/latest/API/API_GetBucketTagging.html)
- [DynamoDB ListTables](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_ListTables.html)
  and [resource tags](https://docs.aws.amazon.com/amazondynamodb/latest/APIReference/API_ListTagsOfResource.html)
- [Recovery points by resource](https://docs.aws.amazon.com/aws-backup/latest/APIReference/API_ListRecoveryPointsByResource.html)
  and [continuous ID prefix](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery-finding.html)
- [Lambda runtime dependencies](https://docs.aws.amazon.com/lambda/latest/dg/python-package.html)
- [SNS KMS publishers](https://docs.aws.amazon.com/sns/latest/dg/sns-key-management.html)

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_archive"></a> [archive](#requirement\_archive) | >= 2.4.0, < 3.0.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.72.0, < 6.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | 2.8.1 |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 5.100.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.health](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_dynamodb_table.incidents](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dynamodb_table) | resource |
| [aws_iam_role.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.scheduler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_lambda_function.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_function_event_invoke_config.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function_event_invoke_config) | resource |
| [aws_scheduler_schedule.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule) | resource |
| [aws_scheduler_schedule_group.coverage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/scheduler_schedule_group) | resource |
| [terraform_data.configuration](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [archive_file.coverage](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_solution_prefix"></a> [solution\_prefix](#input\_solution\_prefix) | Account-global unique consumer and regional prefix, 2-45 alphanumeric, hyphen or underscore characters. | `string` | n/a | yes |
| <a name="input_coverage_policy"></a> [coverage\_policy](#input\_coverage\_policy) | Explicit whole-second freshness/grace/reminder thresholds and rate schedule (minutes or hours). No retention or backup-job inference. | <pre>object({<br/>    max_backup_age_seconds      = number<br/>    freshness_tolerance_seconds = number<br/>    initial_grace_seconds       = number<br/>    reminder_interval_seconds   = number<br/>    schedule                    = string<br/>  })</pre> | `null` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Create the scanner and health resources. Disabled mode needs no coverage configuration. | `bool` | `true` | no |
| <a name="input_expected_resource_tags"></a> [expected\_resource\_tags](#input\_expected\_resource\_tags) | Independent expected-inventory tags. Every key/value must match (AND). Required when enabled. | `map(string)` | `{}` | no |
| <a name="input_resource_types"></a> [resource\_types](#input\_resource\_types) | Explicit inventory discovery types: DynamoDB tables and S3 general purpose buckets only. | `set(string)` | `[]` | no |
| <a name="input_sns_kms_key_arn"></a> [sns\_kms\_key\_arn](#input\_sns\_kms\_key\_arn) | Caller-owned SNS customer-managed symmetric KMS key ARN in the provider account and Region. Required when enabled; caller retains key-policy ownership. | `string` | `null` | no |
| <a name="input_sns_topic_arn"></a> [sns\_topic\_arn](#input\_sns\_topic\_arn) | Caller-owned standard SNS topic in the provider account and Region. Required when enabled. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional scanner infrastructure tags. Do not include expected workload tags on the incident table. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_execution_role_arn"></a> [execution\_role\_arn](#output\_execution\_role\_arn) | Publisher role ARN for caller-owned topic/key policies, or null when disabled. |
| <a name="output_health_alarm_arns"></a> [health\_alarm\_arns](#output\_health\_alarm\_arns) | Health alarm ARN map, or null when disabled. |
| <a name="output_incident_table_arn"></a> [incident\_table\_arn](#output\_incident\_table\_arn) | Incident-state table ARN, or null when disabled. |
| <a name="output_lambda_function_arn"></a> [lambda\_function\_arn](#output\_lambda\_function\_arn) | Coverage scanner Lambda ARN, or null when disabled. |
| <a name="output_schedule_arn"></a> [schedule\_arn](#output\_schedule\_arn) | Scanner schedule ARN, or null when disabled. |
<!-- END_TF_DOCS -->
