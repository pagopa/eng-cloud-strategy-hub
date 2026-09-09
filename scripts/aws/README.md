# AWS Terraform Scripts

Operator-facing Bash scripts for AWS Terraform roots and S3 remote-state bootstrap. Each script has its own operator README; this file is the directory index.

## Contents

- [Scripts](#scripts)
- [Choose an entry point](#choose-an-entry-point)
- [Validation](#validation)
- [Related documentation](#related-documentation)

## Scripts

| Script | README | Role |
| --- | --- | --- |
| [`terraform.sh`](terraform.sh) | [`terraform.sh.README.md`](terraform.sh.README.md) | Standard, project-agnostic AWS Terraform wrapper. |
| [`terraform-dynamic-states.sh`](terraform-dynamic-states.sh) | [`terraform-dynamic-states.sh.README.md`](terraform-dynamic-states.sh.README.md) | Dynamic S3 state-key wrapper with lock inventory and bulk-unlock paths. |
| [`aws-terraform-s3-state-creator.sh`](aws-terraform-s3-state-creator.sh) | [`aws-terraform-s3-state-creator.sh.README.md`](aws-terraform-s3-state-creator.sh.README.md) | S3 remote-state bucket bootstrap and security baseline. |

The scripts do not store live Terraform state or credentials in the repository. Backend configuration, variable files, AWS profiles, and provider credentials remain inputs supplied by the operator or by the selected Terraform root. The parent directory README documents the cross-cloud boundary: [scripts/README.md](../README.md).

## Choose an entry point

- Use [`terraform.sh.README.md`](terraform.sh.README.md) for ordinary AWS Terraform roots with optional `backend.ini` context resolution.
- Use [`terraform-dynamic-states.sh.README.md`](terraform-dynamic-states.sh.README.md) when one `env/backend.dynamic.ini` derives an isolated S3 state key for each scope.
- Use [`aws-terraform-s3-state-creator.sh.README.md`](aws-terraform-s3-state-creator.sh.README.md) to create or align the S3 bucket used by a remote-state backend.

Both Terraform wrappers support a literal `noenv` mode for skipping environment-specific backend and AWS context resolution. Review each script's dedicated README before using `apply`, `destroy`, `unlock`, `unlock-all`, or bucket-creator apply mode.

## Validation

Run the closest safe check for the script being changed:

```bash
bash -n scripts/aws/terraform.sh \
  scripts/aws/terraform-dynamic-states.sh \
  scripts/aws/aws-terraform-s3-state-creator.sh

shellcheck -s bash -x scripts/aws/terraform.sh \
  scripts/aws/terraform-dynamic-states.sh \
  scripts/aws/aws-terraform-s3-state-creator.sh

make terraform-wrapper-tests
make aws-s3-state-creator-tests
bash tests/scripts/aws_terraform_dynamic_states/run.sh
```

The repository workflow [`.github/workflows/terraform-sh-tests.yml`](../../.github/workflows/terraform-sh-tests.yml) runs the syntax checks, ShellCheck, the standard wrapper simulation suite, the dynamic-state simulation suite, and the S3 state-creator suite. The dynamic-state suite has no dedicated Make target and is invoked directly.

## Related documentation

- [Terraform Operator Tooling rules](../../docs/domain/terraform-operator-tooling/RULES.md) — required context selection and destructive-action guard.
- [Scripts overview](../README.md) — cross-cloud wrapper boundary and common entry points.
- [Architecture and testing guidance](../../docs/architecture.md) — repository flows and validation ownership.
- [Standard wrapper simulation suite](../../tests/scripts/terraform_wrappers/run.sh).
- [Dynamic-state simulation suite](../../tests/scripts/aws_terraform_dynamic_states/run.sh).
- [S3 state-creator simulation suite](../../tests/scripts/aws_terraform_s3_state_creator/run.sh).
