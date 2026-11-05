# eng-cloud-strategy-hub

Governance and enablement assets for GitHub Copilot customization, reusable GitHub Actions, cross-cloud Terraform wrappers, and their offline validation surfaces.

## Contents

- [Purpose](#purpose)
- [Repository map](#repository-map)
- [Reader paths](#reader-paths)
- [Validation](#validation)

## Purpose

This repository is a standards and operator-tooling hub. It does not host a single deployable application or live cloud state. Its source-managed governance assets live under `.github/`; reusable actions, Terraform wrappers, local workflow simulation, and offline tests provide the executable surfaces.

## Repository map

| Path | Responsibility | Reader entry point |
| --- | --- | --- |
| `.github/` | Copilot instructions, workflow definitions, validation scripts, and pull request templates. | [.github/README.md](.github/README.md) |
| `actions/global/` | Reusable composite actions for pull request validation, pre-commit, release, and stale pull request handling. | Existing action READMEs in each action directory |
| `scripts/` | AWS, Azure, and GCP Terraform wrappers plus the AWS state-bucket creator. | [scripts/README.md](scripts/README.md) |
| `tools/validate_repo_locally/` | Python runner that simulates selected GitHub Actions checks locally. | [docs/architecture.md](docs/architecture.md#10-testing-and-validation) |
| `tests/` | Python action tests and shell simulation fixtures for wrapper behavior. | [docs/architecture.md](docs/architecture.md#10-testing-and-validation) |
| `docs/` | Architecture, agent-facing repository guides, and retained technical documentation. | [docs/architecture.md](docs/architecture.md) |
| `tmp/` | Disposable and retained planning or diagnostic artifacts; not a runtime surface. | [AGENTS.local.md](AGENTS.local.md) |

## Reader paths

- Contributors should read [AGENTS.md](AGENTS.md), [AGENTS.local.md](AGENTS.local.md), and [docs/architecture.md](docs/architecture.md) before structural changes.
- GitHub Actions consumers should choose the relevant README under `actions/global/` and pin the wrapper action in their workflow.
- Terraform operators should start with [scripts/README.md](scripts/README.md), then use the provider-specific wrapper and its offline simulation suite.
- Agents should read [CONTEXT-MAP.md](CONTEXT-MAP.md) and [docs/agents/domain.md](docs/agents/domain.md) when a change crosses repository domains.

No diagram is provided because the repository-wide relationships are maintained once in [docs/architecture.md](docs/architecture.md#2-system-overview), rather than redrawn in this navigation document.

## Validation

The repository exposes these safe local checks:

```bash
make terraform-wrapper-tests
make aws-s3-state-creator-tests
./validate-repo-locally.sh --list
bash .github/scripts/validate-copilot-customizations.sh --help
```

The full workflow simulator is available through `make validate-local`; its individual steps and prerequisites are documented in [docs/architecture.md](docs/architecture.md#10-testing-and-validation).
