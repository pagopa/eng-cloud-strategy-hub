# `terraform.sh`

Azure operator wrapper for Terraform roots. It resolves an environment directory, optional backend and variable files, Azure subscription context, plan summaries, lock handling, diagnostics, and local cleanup before invoking Terraform.

## Purpose

Use this script when a Terraform root follows the repository's Azure layout and the selected environment lives under `env/<name>`. The literal `noenv` mode skips environment-specific backend and Azure authentication resolution.

## Usage

Run these examples from this directory. The wrapper resolves `env/<name>` from
the current working directory, so the plan example enters a checked-in
synthetic root after capturing the local script path:

```bash
bash ./terraform.sh help
script_path="$(pwd)/terraform.sh"
(
	cd ../../../tests/scripts/terraform_wrappers/fixtures/azure-root
	bash "${script_path}" plan noenv --no-default-tfvars --dry-run
	bash "${script_path}" summ noenv --summary-format pr --dry-run
)
```

General form:

```bash
terraform_root="/path/to/terraform-root"
script_path="$(pwd)/terraform.sh"
(
	cd "${terraform_root}"
	bash "${script_path}" <action> <environment|noenv> [file.tf] [wrapper options] [terraform arguments]
)
```

Common actions are `help`, `list`, `plan`, `apply`, `clean`, `doctor`, `debug-bundle`, `summ`, `tlock`, and `unlock`. Use `--dry-run` to print commands without executing them, `--tfvars <file>` for explicit variable files, and `--no-default-tfvars` to disable automatic variable-file lookup.

## Dependencies

- Bash;
- `terraform` for Terraform actions;
- Azure CLI when the selected environment requires subscription or authentication checks;
- `tf-summarize` for `summ`.

## Validation

```bash
bash -n ./terraform.sh
make -C ../../../ terraform-wrapper-tests
```

The wrapper simulation suite uses fake cloud CLIs and synthetic fixtures; it does not access an Azure subscription or a remote Terraform backend.

## Related documentation

- [Scripts overview](../../README.md).
- [Terraform Operator Tooling rules](../../../docs/domain/terraform-operator-tooling/RULES.md).
- [Wrapper simulation suite](../../../tests/scripts/terraform_wrappers/run.sh).
