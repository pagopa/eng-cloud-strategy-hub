# `terraform.sh`

Project-agnostic Terraform wrapper for AWS roots. It resolves an optional AWS backend context, discovers variable files, initializes Terraform when required, and forwards the selected action and remaining arguments to Terraform.

## Contents

- [Purpose](#purpose)
- [Usage](#usage)
- [Context and inputs](#context-and-inputs)
- [Actions](#actions)
- [Outputs and safety](#outputs-and-safety)
- [Dependencies](#dependencies)
- [Validation](#validation)
- [Related documentation](#related-documentation)

## Purpose

Use [`terraform.sh`](terraform.sh) as the AWS operator entry point for a Terraform root. The wrapper provides common action handling for plan, apply, destroy, summaries, provider locks, workspaces, unlocks, diagnostics, and local cleanup while keeping the provider-specific file boundary separate from the Azure and GCP wrappers.

The wrapper does not store live state or credentials. It reads backend and variable-file inputs from the selected root and exports AWS profile and region values for Terraform to consume.

## Usage

```bash
bash scripts/aws/terraform.sh help
bash scripts/aws/terraform.sh plan dev \
  --root tests/scripts/terraform_wrappers/fixtures/aws-root \
  --dry-run
bash scripts/aws/terraform.sh summ dev \
  --root tests/scripts/terraform_wrappers/fixtures/aws-root \
  --summary-format pr \
  --dry-run
bash scripts/aws/terraform.sh unlock noenv \
  --lock-id 00000000-0000-0000-0000-000000000000 \
  --dry-run
```

General form:

```text
bash scripts/aws/terraform.sh <action> [context] [target.tf] [wrapper options] [terraform arguments]
```

Select the Terraform root with `--root <dir>` or `TERRAFORM_ROOT`. If neither is supplied, the script-directory default is used. The selected root can resolve an optional context in this order:

1. `<root>/<context>/backend.ini`
2. `<root>/env/<context>/backend.ini`

With no context, `<root>/backend.ini` is used when it exists. The literal `noenv` skips environment-specific backend resolution.

## Context and inputs

| Input | Behavior |
| --- | --- |
| `backend.ini` | `profile` or `aws_profile` selects `AWS_PROFILE`; `region` or `aws_region` selects `AWS_REGION` and `AWS_DEFAULT_REGION`. |
| Variable files | Actions that consume variables discover `.tfvars` and `.tfvars.json` files in the selected input directory. `--tfvars <file>` adds explicit overrides. |
| `--no-default-tfvars` | Disables automatic variable-file discovery while retaining explicit `--tfvars` overrides. |
| `target.tf` | For `plan`, `apply`, and `destroy`, resource and module blocks are converted to Terraform `-target` arguments. |
| `--tfplan <file>` | Lets `apply` consume a saved plan. A forwarded `-auto-approve` is removed for this saved-plan path. |
| Remaining arguments | Unrecognized wrapper arguments are forwarded to Terraform; use `--` to make the boundary explicit. |

The wrapper adds `-compact-warnings` to its main `plan`, `apply`, `destroy`, `refresh`, and `console` commands. `--cicd`/`--ci`, or a truthy `CI` value, enables `TF_IN_AUTOMATION` and `TF_INPUT`.

Supported wrapper options include:

- `--root <dir>` or `TERRAFORM_ROOT` for root selection;
- repeatable `--tfvars <file>` and `--init-arg <arg>`;
- `--no-default-tfvars`, `--cicd`/`--ci`, `--dry-run`, and `--skip-init`;
- `--summary-format <format>` with `table`, `markdown`, `tree`, `separate-tree`, `json`, `json-sum`, `html`, or `pr`;
- `--tfplan <file>` and `--summary-out <file>` for plan summaries;
- `--lock-id`, `--from-log`, and `--force` for `unlock`.

## Actions

| Action | Behavior |
| --- | --- |
| `plan`, `apply`, `destroy`, `refresh`, `console` | Run the corresponding Terraform action. `plan`, `apply`, and `destroy` may take the `target.tf` shortcut. |
| `init` | Run `terraform init -reconfigure`, unless `--skip-init` is supplied. |
| `summ` | Create a plan and pass it to the required `tf-summarize` binary. |
| `tlock` | Run `terraform providers lock` for Windows, macOS Intel, macOS Apple Silicon, Linux Intel, and Linux ARM64. |
| `unlock` | Resolve a lock ID from `--lock-id`, `--from-log`, or a lock-probing plan, then prepare or run `terraform force-unlock`. |
| `list` | List Terraform workspaces. |
| `doctor` | Run non-destructive checks for Terraform, variable-file overrides, and local initialization. |
| `debug-bundle` | Write a temporary local diagnostic bundle with execution metadata, variable-file paths, Terraform version, and initialized-root details when available. |
| `clean` | Remove `.terraform`, `tfplan`, and `tfplan.*` from the selected root. |
| `tflist` | Pipe `terraform state list` through an installed `tflist` formatter. |
| Any other action | Forward the action to Terraform. |

Actions that require initialization run `terraform init -reconfigure` first. `--skip-init` suppresses this step.

## Outputs and safety

The wrapper writes preflight, work-phase, and verdict information to standard output. `summ` can emit the formats accepted by `tf-summarize`; `debug-bundle` reports the temporary bundle path.

`plan`, `summ`, `doctor`, and `debug-bundle` are intended for inspection. `apply`, `destroy`, and `unlock` can change external state. Provider-lock updates can change the selected root's local lock file. `--dry-run` prints command-running paths without executing them.

`clean` is different: it removes local artifacts directly and does not use the command runner's dry-run handling. Do not treat `--dry-run` as a safeguard for `clean`. The target-file shortcut also carries risk because targeted runs can hide dependencies; the wrapper emits a warning when it derives `-target` arguments.

`unlock` requires deliberate handling. Without `--force`, the operator must type `unlock` exactly. The wrapper warns that `terraform force-unlock` should be used only for a lock the operator owns or has identified as orphaned.

## Dependencies

- Bash;
- `terraform` for Terraform actions and diagnostics that query Terraform;
- `tf-summarize` for `summ`;
- `tflist` for the optional `tflist` compatibility action;
- AWS credentials and any configured AWS profile for AWS-backed Terraform roots.

The wrapper itself exports profile and region context; it does not store credentials or live backend state in this repository.

## Validation

```bash
bash -n scripts/aws/terraform.sh
shellcheck -s bash -x scripts/aws/terraform.sh
make terraform-wrapper-tests
```

The wrapper simulation suite uses fake cloud CLIs and synthetic fixtures. It exercises this AWS wrapper together with the aligned Azure and GCP wrappers without using live cloud accounts or remote Terraform backends.

## Related documentation

- [AWS scripts index](README.md).
- [Scripts overview](../README.md).
- [Terraform Operator Tooling rules](../../docs/domain/terraform-operator-tooling/RULES.md).
- [Standard wrapper simulation suite](../../tests/scripts/terraform_wrappers/run.sh).
- [Terraform shell-test workflow](../../.github/workflows/terraform-sh-tests.yml).
