# `terraform-dynamic-states.sh`

Terraform wrapper for AWS roots that derive isolated S3 state keys from one dynamic backend configuration. For a scope such as `dev`, it generates `<s3_key_prefix>/dev/<s3_key_suffix>` and passes the scope to Terraform through a configurable variable for variable-consuming actions.

## Contents

- [Purpose](#purpose)
- [Usage](#usage)
- [Dynamic backend configuration](#dynamic-backend-configuration)
- [Actions and scope](#actions-and-scope)
- [Outputs and safety](#outputs-and-safety)
- [Dependencies](#dependencies)
- [Validation](#validation)
- [Related documentation](#related-documentation)

## Purpose

Use [`terraform-dynamic-states.sh`](terraform-dynamic-states.sh) when multiple scopes share a Terraform root and each scope must use an isolated S3 state object. The wrapper also provides S3-native lock inventory and sequential bulk-unlock operations for dynamic state keys.

It reads the dynamic backend from the current working directory. It does not store live state or credentials in the repository.

## Usage

Run these commands from a Terraform root containing `env/backend.dynamic.ini`:

```bash
bash scripts/aws/terraform-dynamic-states.sh plan dev --dry-run
bash scripts/aws/terraform-dynamic-states.sh summ dev --summary-format pr
bash scripts/aws/terraform-dynamic-states.sh find-locks all --cicd
bash scripts/aws/terraform-dynamic-states.sh unlock-all all --cicd --dry-run
```

General form:

```text
bash scripts/aws/terraform-dynamic-states.sh <action> <scope|noenv> [target.tf] [wrapper options] [terraform arguments]
```

Non-base actions require a scope argument. Use the literal `noenv` to skip dynamic backend and AWS cloud-auth resolution. Use a named scope for Terraform actions and `all` for lock inventory or bulk-unlock actions. `list` is unavailable because dynamic backend mode does not maintain a scope catalog.

## Dynamic backend configuration

For a named scope, the wrapper requires `env/backend.dynamic.ini` with this shape:

```ini
s3_bucket = <state-bucket>
aws_region = <aws-region>
aws_account_name = <provider-context>
s3_key_prefix = <state-prefix>
s3_key_suffix = tfstate
aws_profile = <optional-aws-profile>
state_variable = <optional-terraform-variable>
```

| Key | Required | Effect |
| --- | --- | --- |
| `s3_bucket` | Yes | S3 bucket passed to the backend. |
| `aws_region` or `region` | Yes | AWS region exported to the process and passed to the backend. |
| `aws_account_name` | Yes | Required metadata field. Its value is not validated or sent to the S3 backend. |
| `s3_key_prefix` | Yes | Prefix used to build the dynamic state key; it must not end in `/`. |
| `s3_key_suffix` | Yes | Suffix used to build the dynamic state key; it must not start with `/`. |
| `aws_profile` | No | AWS profile used for provider context and credential checks. |
| `state_variable` | No | Terraform variable receiving the scope. Defaults to `terraform_context_key`. |

For a named scope, the generated backend key is:

```text
<s3_key_prefix>/<scope>/<s3_key_suffix>
```

The configuration must use the `s3_` names for bucket and key settings. Static `s3_key`, unprefixed `bucket`, `key`, `key_prefix`, and `key_suffix` settings are rejected. A configured `state_variable` or `--state-variable` must be a valid Terraform variable name.

## Actions and scope

| Action or option | Behavior |
| --- | --- |
| `plan`, `apply`, `destroy`, `refresh`, `console`, `summ` | Use the generated dynamic backend and pass `-var=<state-variable>=<scope>` when the action consumes variable files. |
| `init`, `tlock`, `doctor`, `debug-bundle`, `tflist` | Provide the corresponding Terraform wrapper utility path. `tflist` requires an installed formatter. |
| `unlock` | Resolve a lock ID from `--lock-id`, `--from-log`, or a lock-probing plan, then prepare or run `terraform force-unlock`. |
| `find-locks <scope|all>` | List `.tflock` objects below the dynamic S3 prefix and parse Terraform lock metadata. |
| `unlock-all <scope|all>` | Inventory locks, reinitialize the backend for each lock, and force-unlock sequentially after confirmation. |
| `--state-variable <name>` | Override the variable that receives the scope. |
| `--debug` | Write sanitized structured debug events to standard error. |
| `--cicd`/`--ci` | Skip interactive AWS credential flows and enable Terraform automation variables. |
| `--dry-run` | Print command-running paths without executing Terraform or unlock mutations; lock inventory still performs read-only S3 discovery. |
| `--tfvars <file>` / `--no-default-tfvars` | Add explicit variable-file overrides or disable automatic variable-file discovery. |
| `--summary-format`, `--tfplan`, `--summary-out` | Control `summ`; supported formats are `table`, `markdown`, `tree`, `separate-tree`, `json`, `json-sum`, `html`, and `pr`. |

In dynamic-state mode, automatic variable files are `env/terraform.tfvars` and, for a safe scope name, `env/<scope>-terraform.tfvars`. Explicit `--tfvars` overrides are added after those files. An optional `target.tf` is converted to Terraform `-target` arguments for `plan`, `apply`, and `destroy`, and the wrapper warns that targeted runs can hide dependencies.

When an AWS profile is configured outside CI mode, the wrapper checks that the profile exists and that credentials work. For an SSO profile it may run `aws sso login`. It always exports the configured AWS region and profile for a named dynamic scope.

## Outputs and safety

The wrapper prints preflight, work-phase, lock-inventory, and verdict information to standard output. `debug-bundle` writes to `tmp/terraform-debug/<timestamp>-aws-<scope>/`, including execution metadata, variable-file paths, a sanitized backend summary, Terraform version, and initialized-root details when available.

`apply`, `destroy`, `unlock`, and `unlock-all` can change remote state or resources. `find-locks` reads S3 lock objects. `unlock` requires the exact confirmation `unlock` unless `--force` is supplied; `unlock-all` requires `unlock-all` unless `--force` is supplied. `--dry-run` skips these mutations and prints the planned commands.

`clean` removes `.terraform`, `tfplan`, and `tfplan.*` from the current root and does not use the command runner's dry-run handling. Do not treat `--dry-run` as a safeguard for `clean`.

## Dependencies

- Bash;
- `terraform` for Terraform actions, initialization, and force-unlock;
- `aws` for configured-profile checks and S3 lock inventory or bulk unlock;
- `jq` for S3 lock metadata parsing;
- `tf-summarize` for `summ`;
- `tflist` for the optional `tflist` compatibility action.

Named dynamic scopes also require an AWS profile or other credentials that can access the configured backend. `--cicd` skips interactive profile validation but does not supply credentials.

## Validation

```bash
bash -n scripts/aws/terraform-dynamic-states.sh
shellcheck -s bash -x scripts/aws/terraform-dynamic-states.sh
bash tests/scripts/aws_terraform_dynamic_states/run.sh
```

The dynamic-state simulation suite uses fake AWS and Terraform CLIs and covers dynamic backend keys, scope variables, dry-run behavior, lock inventory, bulk-unlock planning, and dynamic-context diagnostics without using live cloud accounts or remote Terraform backends.

## Related documentation

- [AWS scripts index](README.md).
- [Scripts overview](../README.md).
- [Terraform Operator Tooling rules](../../docs/domain/terraform-operator-tooling/RULES.md).
- [Dynamic-state simulation suite](../../tests/scripts/aws_terraform_dynamic_states/run.sh).
- [Terraform shell-test workflow](../../.github/workflows/terraform-sh-tests.yml).
