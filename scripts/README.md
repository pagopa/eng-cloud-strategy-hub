# Terraform Operator Wrappers

Provider-specific Bash wrappers expose one operator-facing Terraform command contract for AWS, Azure, and GCP, with a separate AWS state-bucket creator for bootstrapping remote state.

## Contents

- [Purpose](#purpose)
- [Wrappers](#wrappers)
- [Usage](#usage)
- [Validation](#validation)

## Purpose

The scripts in this directory coordinate Terraform with provider CLI context,
environment-specific backend and variable files, plan summaries, lock handling,
and non-destructive diagnostics. They do not own live state or provider
credentials.

## Wrappers

| Path | Responsibility | Execution context |
| --- | --- | --- |
| `aws/terraform.sh` | Terraform wrapper for AWS roots. | AWS CLI profile and region resolution when an environment requires it. |
| `azure/terraform.sh` | Terraform wrapper for Azure roots. | Azure subscription resolution when an environment requires it. |
| `gcp/terraform.sh` | Terraform wrapper for GCP roots. | GCP project resolution when an environment requires it. |
| `aws/aws-terraform-s3-state-creator.sh` | Creates or validates the AWS S3 state-bucket bootstrap resources. | AWS CLI and explicitly supplied bootstrap inputs. |

The three Terraform wrappers intentionally remain separate files while exposing the same top-level actions and options. `noenv` skips environment-specific backend and cloud-auth resolution; `--dry-run` prints commands without executing them.

## Usage

Run a wrapper with the current working directory set to a Terraform root. The
wrappers do not accept a separate root-path argument. This safe example uses a
checked-in synthetic root and dry-run mode:

```bash
hub_root="$(pwd)"
scripts/aws/terraform.sh help
(
	cd tests/scripts/terraform_wrappers/fixtures/azure-root
	"${hub_root}/scripts/azure/terraform.sh" plan noenv --no-default-tfvars --dry-run
)
```

Common actions include `help`, `list`, `plan`, `apply`, `clean`, `doctor`, `debug-bundle`, `summ`, `tlock`, and `unlock`. Provider-specific backend and variable-file conventions are resolved from the current Terraform root and its environment or project directory.

The AWS state creator is a separate bootstrap path. Use its test suite as the local contract before running it against a real account.

## Validation

The offline suites use fake cloud CLIs and synthetic fixtures:

```bash
make terraform-wrapper-tests
make aws-s3-state-creator-tests
bash -n scripts/aws/terraform.sh scripts/azure/terraform.sh scripts/gcp/terraform.sh
```

The corresponding workflow is [.github/workflows/terraform-sh-tests.yml](../.github/workflows/terraform-sh-tests.yml). It runs Bash syntax checks, ShellCheck, and both simulation suites without requiring remote Terraform state.

No diagram is provided because the wrapper-to-test relationships are maintained in [docs/architecture.md](../docs/architecture.md#2-system-overview).
