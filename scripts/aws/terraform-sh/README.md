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

Run these examples from this directory (`scripts/aws/terraform-sh`):

```bash
bash ./terraform.sh help
bash ./terraform.sh plan dev \
  --root ../../../tests/scripts/cross-provider/terraform-sh/fixtures/aws-root \
  --dry-run
bash ./terraform.sh summ dev \
  --root ../../../tests/scripts/cross-provider/terraform-sh/fixtures/aws-root \
  --summary-format pr \
  --dry-run
bash ./terraform.sh unlock noenv \
  --lock-id 00000000-0000-0000-0000-000000000000 \
  --dry-run
```

General form:

```text
bash ./terraform.sh <action> [context] [target.tf] [wrapper options] [terraform arguments]
```

Select the Terraform root with `--root <dir>` or `TERRAFORM_ROOT`. If neither is supplied, the AWS scripts directory is used. The selected root can resolve an optional context in this order:

1. `<root>/<context>/backend.ini`
2. `<root>/env/<context>/backend.ini`

With no context, `<root>/backend.ini` is used when it exists. The literal `noenv` skips environment-specific backend resolution.

Wrapper actions such as `plan`, `apply`, `destroy`, `summ`, `unlock`, and `init` fail when the context does not exist. Other Terraform subcommands treat an unknown second argument as a Terraform operand, so `state list` and `state dev list` both work. An existing context name always wins over an operand with the same name.

## Context and inputs

| Input | Behavior |
| --- | --- |
| `backend.ini` | `profile` or `aws_profile` selects `AWS_PROFILE`; `region` or `aws_region` selects `AWS_REGION` and `AWS_DEFAULT_REGION`. Every key is passed to `terraform init` as `-backend-config`. Text after whitespace followed by `#` or `;` is an inline comment. |
| Variable files | Actions that consume variables, including `unlock` lock probing, discover `.tfvars` and `.tfvars.json` files in the selected input directory. `--tfvars <file>` adds explicit overrides. |
| `--no-default-tfvars` | Disables automatic variable-file discovery while retaining explicit `--tfvars` overrides. |
| `target.tf` | For `plan`, `apply`, and `destroy`, resource and module blocks are converted to Terraform `-target` arguments. |
| `--tfplan <file>` or a trailing plan file | Lets `apply` consume an existing saved plan. A forwarded `-auto-approve` is removed for this saved-plan path. |
| Remaining arguments | Unrecognized wrapper arguments are forwarded to Terraform; use `--` to make the boundary explicit. For `init`, they are added to `terraform init`. |

The wrapper adds variable files in this order. Terraform gives the last `-var-file` or `-var` the highest precedence:

1. discovered `*.tfvars` and `*.tfvars.json` files, sorted by name;
2. `terraform.tfvars`, then `terraform.tfvars.json`;
3. `--tfvars` overrides, in command-line order;
4. `-var` and `-var-file` arguments forwarded to Terraform.

`TF_VAR_*` environment variables keep the lowest Terraform precedence. When the input directory is also Terraform's working directory, the wrapper skips `*.auto.tfvars` files because Terraform already loads them.

A saved plan cannot be combined with a `target.tf` file, `--tfvars`, or a second saved plan. The wrapper rejects these combinations, and a missing saved plan, before `terraform init`.

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
| `init` | Run `terraform init -reconfigure` with forwarded arguments, unless `--skip-init` is supplied. |
| `summ` | Create a plan and pass it to the required `tf-summarize` binary. |
| `tlock` | Run `terraform providers lock` for Windows, macOS Intel, macOS Apple Silicon, Linux Intel, and Linux ARM64. |
| `unlock` | Initialize the selected backend, resolve a lock ID from `--lock-id`, `--from-log`, or a lock-probing plan, then prepare or run `terraform force-unlock`. |
| `list` | List Terraform workspaces. |
| `doctor` | Run non-destructive checks for Terraform, local initialization, and the variable files that `plan` would use. Missing `--tfvars` overrides are reported as issues. |
| `debug-bundle` | Write a temporary local diagnostic bundle with execution metadata, the variable files that `plan` would use, Terraform version, and initialized-root details when available. |
| `clean` | Remove `.terraform`, `tfplan`, and `tfplan.*` from the selected root. |
| `tflist` | Pipe `terraform state list` through an installed `tflist` formatter. |
| Any other action | Forward the action to Terraform. |

Actions that require initialization run `terraform init -reconfigure` first. `--skip-init` suppresses this step.

## Outputs and safety

Standard output carries only the requested command's output: Terraform output, `tf-summarize` output, help text, and the commands printed by `--dry-run`. Preflight, work phases, `terraform init` output, messages, and the verdict go to standard error. This keeps `output -json` and `summ --summary-format json` usable in pipes.

Terraform plan exit code `2` means changes are present when `-detailed-exitcode` is enabled, including through `TF_CLI_ARGS` or `TF_CLI_ARGS_plan`. The wrapper preserves that code and reports `CHANGES PRESENT` instead of `FAILED`. The `summ` action still generates its summary and then returns `2`; a summary error takes precedence. Other non-zero results are failures. GitHub Actions callers must explicitly handle code `2` when it is an expected result.

`plan`, `summ`, `doctor`, and `debug-bundle` are intended for inspection. `apply`, `destroy`, and `unlock` can change external state. Provider-lock updates can change the selected root's local lock file.

`--dry-run` prints commands without executing them, for every action. With `--dry-run`, `unlock` prints the lock-probing plan instead of running it, `clean` prints the removal command, and `debug-bundle` prints the collection commands without creating a bundle.

Printed commands replace the values of sensitive `backend.ini` keys, such as `access_key`, `secret_key`, and `token`, with `REDACTED`. Terraform still receives the real values. The redaction covers wrapper output only, not Terraform's own output. The target-file shortcut also carries risk because targeted runs can hide dependencies; the wrapper emits a warning when it derives `-target` arguments.

The target-file shortcut reads declarations line by line. It rejects files containing `/*` or `<<` markers, including markers inside strings, before initialization. Use explicit Terraform `-target` arguments for those files. This conservative guard prevents comments and heredoc text from becoming unintended targets without adding an HCL parser.

`unlock` requires deliberate handling. Without `--force`, the operator must type `unlock` exactly. The wrapper warns that `terraform force-unlock` should be used only for a lock the operator owns or has identified as orphaned.

The `unlock` lock-probing plan streams its combined output to standard error and removes its temporary files after execution. A directly invoked GitHub Actions `run` step receives both standard output and standard error; caller redirections can change their visibility.

## Dependencies

- Bash;
- `terraform` for Terraform actions and diagnostics that query Terraform;
- `tf-summarize` for `summ`;
- `tflist` for the optional `tflist` compatibility action;
- AWS credentials and any configured AWS profile for AWS-backed Terraform roots.

The wrapper itself exports profile and region context; it does not store credentials or live backend state in this repository.

## Validation

```bash
bash -n ./terraform.sh
shellcheck -s bash -x ./terraform.sh
make -C ../../../ terraform-wrapper-tests
python3 -m unittest discover -s ../../../tests/scripts/aws/terraform-sh -p 'test_*.py'
```

The wrapper simulation suite uses fake cloud CLIs and synthetic fixtures. It exercises this AWS wrapper together with the aligned Azure and GCP wrappers without using live cloud accounts or remote Terraform backends.

The Python tests in `tests/scripts/aws/terraform-sh/` cover this wrapper only:

- `test_terraform_sh.py` checks behavior with fake binaries;
- `test_terraform_sh_docs.py` checks that the version header, `help` options, and this README stay aligned, and runs the usage examples above;
- `test_terraform_sh_real.py` runs real Terraform with a local backend to prove variable precedence, saved plans, and `-detailed-exitcode`. It is skipped when `terraform` is not installed.

## Related documentation

- [AWS scripts index](../README.md).
- [Scripts overview](../../README.md).
- [Terraform Operator Tooling rules](../../../docs/domain/terraform-operator-tooling/RULES.md).
- [Cross-provider wrapper simulation suite](../../../tests/scripts/cross-provider/terraform-sh/run.sh).
- [AWS wrapper behavior tests](../../../tests/scripts/aws/terraform-sh/test_terraform_sh.py).
- [Code analysis workflow](../../../.github/workflows/_code-analysis.yml).
