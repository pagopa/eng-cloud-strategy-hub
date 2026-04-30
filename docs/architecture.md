# AI Architecture Contract v1.1.0

## Repository

`eng-cloud-strategy-hub` is a hub repository for shared cloud strategy assets, reusable infrastructure, Terraform modules, GitHub Actions packaging, and platform scaffolding examples.

## Purpose

The repository functions as a reuse and distribution hub rather than a single application. It contains reusable actions, code templates, infrastructure roots, and Terraform modules used to standardize cloud strategy delivery.

## System Boundaries

In scope:

- Reusable action and automation assets under `actions/`.
- Shared or sample code assets under `code/`.
- Platform infrastructure under `infra/ppa-cloud-strategy/`.
- Terraform root and modules under `terraform/` and `terraform/modules/`.
- Release and pre-commit workflows under `.github/workflows/`.

Out of scope:

- Direct ownership of consumer application runtime behavior.
- Provider-specific authorization or governance data owned by sibling repositories.
- Ad hoc local customization not represented in reusable assets.

## Main Components

| Component | Path | Responsibility |
| --- | --- | --- |
| Reusable actions | `actions/` | Shared automation/action assets. |
| Code assets | `code/` | Shared examples, templates, or supporting code. |
| Platform infrastructure | `infra/ppa-cloud-strategy/` | Environment-oriented platform infrastructure with Terraform scripts. |
| Terraform root | `terraform/` | Hub Terraform entrypoint. |
| Terraform modules | `terraform/modules/` | Reusable modules for backend, backup, Cognito, database, DNS, frontend, IAM, monitoring, network, API, messaging, storage, and related concerns. |
| Workflows | `.github/workflows/` | Pre-commit, release, PR hygiene, and stale PR operations. |

## Architecture Flow

```text
Reusable code, actions, and infrastructure modules
  -> hub Terraform roots and module consumers
  -> workflow packaging and release process
  -> downstream reuse by cloud strategy projects
```

The repository is modular. The `terraform/modules/` tree is the clearest reusable architecture surface, while `infra/ppa-cloud-strategy/` contains a concrete platform infrastructure implementation.

## Validation Surface

Observed validation surfaces include:

- Workflows `_pre-commit.yml`, `pr-stale-close.yml`, `pr-title.yml`, and `release.yml`.
- Terraform helper scripts under `infra/ppa-cloud-strategy/scripts/`.
- `ct.yaml` and `force.release` as release/chart or packaging control surfaces.

No `tests/` directory or `Makefile` targets were observed in the current workspace structure.

## Operational Notes

- Keep reusable modules generic and avoid embedding consumer-specific assumptions.
- Keep concrete platform deployment logic in `infra/ppa-cloud-strategy/` rather than mixing it into generic modules.
- Preserve module boundaries when adding new infrastructure capabilities.
- Treat releases as the distribution mechanism for reusable assets.

## Risks And Open Questions

| Risk | Current evidence | Recommended handling |
| --- | --- | --- |
| Hub and concrete implementation can blur | Both `terraform/modules/` and `infra/ppa-cloud-strategy/` exist. | Keep reusable module contracts separate from platform-specific roots. |
| Limited observed tests | No `tests/` directory observed. | Add module examples or validation checks when changing reusable module behavior. |
| Asset ownership unclear from README headings | README has minimal headings. | Keep `docs/architecture.md` and module docs current as the navigational layer. |

## Contract Status

This repository is ready for AI Architecture Contract v1.1.0 as a shared cloud strategy hub. The contract should be strengthened when module-level validation or consumer usage documentation is added.
