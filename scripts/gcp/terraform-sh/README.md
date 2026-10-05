# `terraform.sh`

GCP operator wrapper for Terraform roots. It resolves a project directory, optional backend and variable files, GCP project context, plan summaries, lock handling, diagnostics, and local cleanup before invoking Terraform.

## Purpose

Use this script when a Terraform root follows the repository's GCP layout and the selected project lives under `projects/<name>`. The literal `noenv` mode skips project-specific backend and GCP authentication resolution.

## Usage

Run these examples from this directory. The wrapper resolves `projects/<name>`
from the current working directory, so the plan example enters a checked-in
synthetic root after capturing the local script path:

```bash
bash ./terraform.sh help
script_path="$(pwd)/terraform.sh"
(
	cd ../../../tests/scripts/cross-provider/terraform-sh/fixtures/gcp-root
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
	bash "${script_path}" <action> <project|noenv> [file.tf] [wrapper options] [terraform arguments]
)
```

Common actions are `help`, `list`, `plan`, `apply`, `clean`, `doctor`, `debug-bundle`, `summ`, `tlock`, and `unlock`. Use `--dry-run` to print commands without executing them, `--tfvars <file>` for explicit variable files, and `--no-default-tfvars` to disable automatic variable-file lookup.

The state project used by the wrapper can be supplied through `TF_STATE_PROJECT_ID` when the backend configuration requires it.

## Dependencies

- Bash;
- `terraform` for Terraform actions;
- Google Cloud CLI when the selected project requires authentication or context checks;
- `tf-summarize` for `summ`.

## Validation

```bash
bash -n ./terraform.sh
make -C ../../../ terraform-wrapper-tests
```

The wrapper simulation suite uses fake cloud CLIs and synthetic fixtures; it does not access a GCP project or a remote Terraform backend.

## Related documentation

- [Scripts overview](../../README.md).
- [Terraform Operator Tooling rules](../../../docs/domain/terraform-operator-tooling/RULES.md).
- [Wrapper simulation suite](../../../tests/scripts/cross-provider/terraform-sh/run.sh).
