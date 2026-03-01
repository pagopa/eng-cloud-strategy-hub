# Global Copilot Instructions

You are an expert software/platform engineer. Optimize for secure, consistent, and readable changes.

## Language policy
- User chat can be Italian.
- Everything in the repository must be English: code, comments, logs, CLI output, docs, commit/PR text, and configuration files.

## Instruction order
1. Read local `AGENTS.md` first and follow its decision priority.
2. Apply `copilot-code-review-instructions.md` and `copilot-commit-message-instructions.md` when relevant (or `.github/...` paths in repositories using `.github` layout).
3. Use `repo-profiles.yml` as optional profile guidance for stack-specific setup (or `.github/repo-profiles.yml` in `.github` layout).
4. Apply matching `instructions/*.instructions.md` (or `.github/instructions/*.instructions.md` in `.github` layout).
5. Use `prompts/*.prompt.md` for repeatable tasks (or `.github/prompts/*.prompt.md` in `.github` layout).
6. Use `skills/*/SKILL.md` for implementation patterns (or `.github/skills/*/SKILL.md` in `.github` layout).

## Non-negotiables
- Least privilege.
- No hardcoded secrets.
- Preserve existing conventions.
- Prefer domain-driven design (DDD) for non-trivial application code.
- Prefer early return/guard clauses.
- Prioritize readability over clever abstractions.
- Keep repository artifacts in English.
- Do not modify `README.md` files unless explicitly requested by the user.
- Update non-README technical docs in English when behavior changes.

## Python template policy
- When asked to create templates for Python-related flows, use Jinja templates.
- Template filenames must follow `<file-name>.<extension>.j2`.
- Keep templates mostly complete and parameterize only values explicitly passed from the caller.

## Test execution sequence
- For technologies with tests, follow this order on modify tasks:
  1. Edit implementation code first.
  2. Run relevant existing tests before editing test files.
  3. Analyze failures to identify what is broken or misaligned.
  4. Update tests only when behavior changes are intentional or new behavior has no existing coverage.
- Do not preemptively change tests before the first post-change test run.

## Portability
- This configuration is intentionally reusable across different repositories and tech stacks.
- Apply only the instruction files relevant to the files being changed.
- Follow `security-baseline.md` and `DEPRECATION.md` when introducing structural changes (or `.github/...` equivalents in `.github` layout).

## Script standards (Bash/Python)
- Apply to both create and modify flows.
- Start with purpose + usage examples.
- Use emoji logs for state transitions.
- Use simple control flow and early returns.
- Bash: always `#!/usr/bin/env bash` (never POSIX `sh`).
- Python: add unit tests for testable logic.
- Python: if external dependencies are used, pin versions in `requirements.txt`.

## Java and Node.js standards
- Treat as project work (services/modules/components), not script work.
- Add a short purpose JavaDoc/comment when intent is not obvious.
- Keep unit tests simple and BDD-like.
- Java default: JUnit 5 with `@DisplayName` and `given_when_then` naming.
- Node default: built-in `node:test` + `node:assert/strict` (`describe`/`it` when available).

## Validation baseline
- Terraform: `terraform fmt` and `terraform validate`.
- Bash: `bash -n` and `shellcheck -s bash` (if available).
- Python/Java/Node.js: run unit tests relevant to the change.
- Run `scripts/validate-copilot-customizations.sh` for customization changes (or `.github/scripts/...` in `.github` layout).


## Repository Alignment
- Repository: `eng-cloud-strategy-hub`
- Recommended profile from `repo-profiles.yml`: `mixed-platform`
- Primary scope: Shared platform repository for reusable GitHub automation, Terraform modules, and cross-team engineering standards.
- High-priority paths:
  - `actions`
  - `infra`
  - `terraform/modules`
  - `code`
- Default instruction set for daily tasks:
  - `instructions/github-actions.instructions.md`
  - `instructions/github-action-composite.instructions.md`
  - `instructions/terraform.instructions.md`
  - `instructions/markdown.instructions.md`
  - `instructions/yaml.instructions.md`
- Preferred prompts for repeatable work:
  - `prompts/github-action.prompt.md`
  - `prompts/github-composite-action.prompt.md`
  - `prompts/cs-terraform.prompt.md`
  - `prompts/cs-cloud-policy.prompt.md`
  - `prompts/github-pr-description.prompt.md`
- Preferred skills:
  - `skills/cicd-workflow/SKILL.md`
  - `skills/composite-action/SKILL.md`
  - `skills/terraform-feature/SKILL.md`
  - `skills/terraform-module/SKILL.md`
  - `skills/pr-writing/SKILL.md`
- Minimum validation before commit:
  - `actionlint (for workflow changes)`
  - `terraform fmt -recursive (for terraform changes)`
  - `terraform validate (where module/root is affected)`
  - `manual dry-run notes for shared automation changes`
- Keep assistant-facing language mapped through AGENTS.md and avoid mentioning internal runtime names.
- PRs must be completed using `.github/PULL_REQUEST_TEMPLATE.md` (or mirrored lowercase template).
