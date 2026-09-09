# `aws-terraform-s3-state-creator.sh`

AWS operator bootstrap tool that creates or aligns a dedicated S3 bucket for Terraform remote state. It verifies the caller's AWS account, detects whether the bucket is new or existing, renders a control plan, and applies a recovery-oriented security baseline after confirmation.

## Contents

- [Purpose](#purpose)
- [Usage](#usage)
- [Inputs](#inputs)
- [Workflow and controls](#workflow-and-controls)
- [Outputs and safety](#outputs-and-safety)
- [Dependencies](#dependencies)
- [Validation](#validation)
- [Related documentation](#related-documentation)

## Purpose

Use [`aws-terraform-s3-state-creator.sh`](aws-terraform-s3-state-creator.sh) to bootstrap or recover the S3 bucket used by a Terraform remote-state backend. The script distinguishes `CREATE` and `UPDATE` operations and applies the same security baseline to both paths where applicable.

It does not create a repository file, manage live Terraform state, configure Terraform locking, manage lifecycle retention, or enable S3 Object Lock.

## Usage

```bash
bash scripts/aws/aws-terraform-s3-state-creator.sh \
  --region eu-south-1 \
  --account-name sandbox \
  --bucket my-tf-state \
  --dry-run

bash scripts/aws/aws-terraform-s3-state-creator.sh \
  --region eu-south-1 \
  --account-name sandbox \
  --bucket my-tf-state \
  --tag Environment=dev \
  --yes
```

General form:

```text
bash scripts/aws/aws-terraform-s3-state-creator.sh [options]
```

## Inputs

Requirements: `aws` and `jq` must be available. The AWS identity must be able to perform the read and write operations required by the selected path.

| Option | Required | Effect |
| --- | --- | --- |
| `--region <aws-region>` | Yes | Region used for bucket operations. |
| `--account-name <name>` | Yes | Expected AWS account name. The script verifies it before continuing. |
| `--bucket <bucket-name>` | Yes | Target S3 bucket. Lowercase S3 naming rules are validated. |
| `--profile <aws-profile>` | No | AWS CLI profile used for all calls. |
| `--tag <Key=Value>` | No, repeatable | Additional tag merged into the bucket tag set. Both key and value must be non-empty. |
| `--dry-run` | No | Render a read-only plan, skip S3 mutations, and skip confirmation. |
| `--yes` | No | Skip the interactive confirmation for an apply. |
| `--help` / `-h` | No | Show usage information. |

The bucket name must be lowercase, 3–63 characters, and satisfy the script's S3 naming validation. The script also rejects reserved or IP-address-shaped names.

## Workflow and controls

1. Obtain the caller ARN and account ID with `sts get-caller-identity`.
2. Resolve the account name with `organizations describe-account`; if that lookup is unavailable, fall back to `account get-account-information`. Compare the result with `--account-name`.
3. Check bucket accessibility with `s3api head-bucket` and select `CREATE` for a missing bucket or `UPDATE` for an accessible bucket. A forbidden bucket can produce only a dry-run plan; a different-region response is an error.
4. Render the planned operation and request confirmation unless `--dry-run` or `--yes` applies.
5. On apply, create a missing bucket and enforce the following baseline:

   - S3 versioning, verified after the write with bounded retries;
   - all four S3 public-access-block settings;
   - `BucketOwnerEnforced` object ownership;
   - default SSE-S3 encryption with AES256;
   - a `DenyInsecureTransport` bucket-policy statement while preserving other policy statements;
   - merged existing, default, and user-supplied tags, subject to the S3 limit of 50 tags.

Every bucket mutation includes the verified `--expected-bucket-owner` guard. Existing lifecycle rules are not changed. Object Lock is intentionally not enabled or managed by this recovery baseline. Configure Terraform backend locking and the required IAM permissions separately in the consuming root.

When a tag key appears more than once, later values win in this order: existing bucket tags, script defaults, then `--tag` values.

## Outputs and safety

The script writes a human-readable plan and progress report to standard output. It performs identity and accessibility reads before an operation. Apply mode can create a bucket or update its controls; `--dry-run` does not issue S3 mutation calls. Without `--yes`, an operator can cancel at the confirmation prompt.

The recovery baseline deliberately leaves lifecycle retention and Object Lock unchanged. Review the account, region, bucket, operation mode, and planned controls before approving an apply.

## Dependencies

- Bash;
- AWS CLI (`aws`);
- `jq` for identity, policy, tag, and response processing;
- an AWS identity with the permissions needed by the selected read or write path.

The script does not store credentials or live bucket state in this repository.

## Validation

```bash
bash -n scripts/aws/aws-terraform-s3-state-creator.sh
shellcheck -s bash -x scripts/aws/aws-terraform-s3-state-creator.sh
make aws-s3-state-creator-tests
```

The S3 state-creator simulation suite uses a fake AWS CLI and covers argument validation, account checks, dry-run behavior, recovery controls, policy and tag merging, versioning verification, and operator cancellation without using a live AWS account.

## Related documentation

- [AWS scripts index](README.md).
- [Scripts overview](../README.md).
- [Terraform Operator Tooling rules](../../docs/domain/terraform-operator-tooling/RULES.md).
- [S3 state-creator simulation suite](../../tests/scripts/aws_terraform_s3_state_creator/run.sh).
- [Terraform shell-test workflow](../../.github/workflows/terraform-sh-tests.yml).
