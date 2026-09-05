# Copilot And Workflow Governance

This directory is the repository-owned source for Copilot customization, GitHub workflow definitions, and the scripts that validate or bootstrap those assets.

## Contents

- [Purpose](#purpose)
- [Included files](#included-files)
- [Change path](#change-path)
- [Validation](#validation)

## Purpose

The `.github/` surface supplies repository instructions and automation entrypoints. It is configuration and policy source material consumed by GitHub Actions and by local validation; it is not an application runtime.

## Included files

| Path | Responsibility |
| --- | --- |
| `copilot-instructions.md` | GitHub.com Copilot code-review guidance. |
| `instructions/` | Path-scoped instructions for repository technologies and authoring tasks. |
| `workflows/` | Pull request, pre-commit, release, code-analysis, and Terraform shell-test workflows. |
| `scripts/bootstrap-copilot-config.sh` | Bootstrap entrypoint for copying Copilot configuration into a target repository. |
| `scripts/validate-copilot-customizations.sh` | Validator for supported Copilot customization layouts and metadata. |
| `PULL_REQUEST_TEMPLATE.md` | Pull request template used by GitHub. |

## Change path

1. Read the repository instructions that apply to the changed asset.
2. Keep workflow and script changes within their existing ownership boundaries.
3. Run the relevant local entrypoint or simulator before opening a pull request.
4. Update [docs/architecture.md](../docs/architecture.md) when a deliberate structural boundary changes.

No diagram is provided because the repository-wide governance-to-validation relationships are maintained in [docs/architecture.md](../docs/architecture.md#2-system-overview).

## Validation

The entrypoint smoke checks are safe and do not apply configuration:

```bash
bash .github/scripts/bootstrap-copilot-config.sh --help
bash .github/scripts/validate-copilot-customizations.sh --help
```

Workflow syntax is checked by the `actionlint` job in `.github/workflows/_code-analysis.yml`; the local simulator exposes that job's relevant steps through `./validate-repo-locally.sh`.
