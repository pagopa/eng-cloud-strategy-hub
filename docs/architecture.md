# AI Architecture Contract v1.2.0

## Repository

`eng-cloud-strategy-hub` is a governance and enablement repository for GitHub Copilot customization, repository automation, and cross-cloud Terraform wrapper tooling.

## Purpose

The repository does not host a single deployable application. It centralizes:

- Copilot governance assets under `.github/`.
- Reusable automation under `actions/`.
- Local workflow simulation tooling under `tools/`.
- Cross-cloud Terraform operator wrappers under `scripts/`.
- Offline validation assets under `tests/`.
- Documentation and retained planning artifacts under `docs/` and `tmp/superpowers/`.
- Reserved placeholder roots under `code/` and `terraform/`.

## System Boundaries

In scope:

- Instruction architecture, skills, agents, prompts, and workflow governance under `.github/`.
- Composite automation assets such as `actions/global/stale-close-pr/`, `actions/global/release/`, `actions/global/pr-title/`, and `actions/global/pre-commit/`.
- Local workflow simulation tools under `tools/validate_repo_locally/` and the root `validate-repo-locally.sh` launcher.
- AWS, Azure, and GCP Terraform wrappers under `scripts/aws/`, `scripts/azure/`, and `scripts/gcp/`.
- Offline simulation fixtures and shell-based tests under `tests/scripts/terraform_wrappers/`.
- Repository documentation and retained execution plans under `docs/` and `tmp/superpowers/`.

Out of scope:

- Live cloud resource state, remote Terraform backends, or production environment ownership.
- Consumer application runtime code.
- Long-lived credentials, secrets, or provider-specific governance data owned elsewhere.

## Main Components

| Component | Path | Responsibility |
| --- | --- | --- |
| Instruction bridge | `AGENTS.md` | Defines repository-wide Copilot governance, precedence, and operating model. |
| Copilot governance layer | `.github/` | Hosts instructions, skills, agents, templates, workflows, and inventory metadata. |
| Reusable actions | `actions/global/` | Provides composite release, PR title validation, pre-commit, and PR stale/auto-close automation consumed by repository workflows. |
| Local action simulator | `tools/validate_repo_locally/`, `validate-repo-locally.sh` | Runs local equivalents of selected workflow checks before GitHub-hosted CI. |
| Terraform wrappers | `scripts/aws/`, `scripts/azure/`, `scripts/gcp/` | Expose a shared operator-facing CLI contract for Terraform across the three cloud providers. |
| Wrapper simulation suite | `tests/scripts/terraform_wrappers/` | Verifies wrapper parity offline with fake CLIs, fixtures, and shell assertions. |
| Documentation surface | `docs/` | Stores architecture and other repository-owned technical documentation. |
| Retained planning workspace | `tmp/superpowers/` | Keeps non-runtime execution plans and work-in-progress artifacts. |
| Reserved placeholders | `code/`, `terraform/` | Hold space for future assets but are not active architecture surfaces today. |

## Architecture Flow

```text
Governance rules, instructions, and reusable automation
  -> repository workflows and local validation enforce the baseline
  -> cross-cloud Terraform wrappers expose a common operator contract
  -> offline simulation tests guard wrapper behavior across AWS, Azure, and GCP
```

The repository is architecture-by-governance rather than architecture-by-runtime. The most active executable surface is the Terraform wrapper layer plus its simulation suite.

## Validation Surface

Observed validation surfaces include:

- `.pre-commit-config.yaml` for YAML, JSON, shell, Python, Terraform, and workflow linting baselines.
- Workflows `_pre-commit.yml`, `pr-stale-close.yml`, `pr-title.yml`, `release.yml`, and `terraform-sh-tests.yml`, with shared workflow logic delegated to `actions/global/` where practical.
- Local workflow simulation through `./validate-repo-locally.sh` for `_code-analysis.yml`, `_pre-commit.yml`, and `terraform-sh-tests.yml`, with a non-interactive default path and an optional interactive selector.
- The shell-based simulation suite at `tests/scripts/terraform_wrappers/run.sh`.
- Local shell validation via `bash -n` and `shellcheck` for the wrapper and test scripts.

## Operational Notes

- The three Terraform wrappers intentionally remain separate files with a shared CLI contract instead of a common Bash library.
- `validate-repo-locally.sh` stays CI-safe by default and bootstraps the toolkit-local virtual environment at `tools/validate_repo_locally/.venv` from the hash-locked `tools/validate_repo_locally/requirements.txt` only when `--interactive` is requested.
- `tests/scripts/terraform_wrappers/fixtures/` is synthetic and exists only to validate wrapper behavior without cloud credentials or remote state.
- `code/` and `terraform/` are placeholders today and should not be documented as active delivery surfaces until real assets exist there.
- `tmp/superpowers/` is a retained working area, not a shipped runtime or reusable API surface.

## Risks And Open Questions

| Risk | Current evidence | Recommended handling |
| --- | --- | --- |
| Wrapper parity can drift | The shared CLI contract is duplicated across three provider-specific scripts. | Keep behavior changes synchronized with the simulation suite and the dedicated workflow. |
| Placeholder roots can be over-interpreted | `code/` and `terraform/` currently contain only `.gitkeep`. | Treat them as reserved space until first-class assets are added and documented. |
| Retained plans can become stale | `tmp/superpowers/` stores execution plans beside active repository code. | Keep plan files updated while work is active and remove or archive them when the work closes. |

## Contract Status

This repository is ready for AI Architecture Contract v1.2.0 as a governance and operator-tooling hub. Any future addition of deployable application code, Terraform modules, or other first-class runtime assets should update this contract in the same change.
