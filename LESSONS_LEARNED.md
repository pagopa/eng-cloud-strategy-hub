# Lessons

This file retains durable lessons discovered while completing tasks in this repository. It is a learning ledger, not the canonical policy source.

## Entry Rules

- Before editing this file, read its current on-disk contents and treat them as the source of truth for in-progress local lessons, including local uncommitted rows already present on disk.
- Record only lessons that were not already codified in repository resources at the time they were learned.
- Also record durable corrections to repeated or consequential misapplication of already-codified repository rules when that correction is likely to prevent future mistakes.
- When a validator, IDE, schema check, or runtime error overturns an earlier assumption, re-check immediately whether the correction is durable enough to retain until it is codified or deliberately dropped.
- Before deciding whether to retain, codify, or drop such a correction, read the relevant primary documentation instead of relying on memory alone.
- Prefer the smallest canonical home: if the correction belongs in a scoped instruction, skill, agent, or repository config and is being codified there, do not retain a duplicate lesson row.
- Keep only stable, reusable, repository-relevant lessons.
- Do not retain incident-specific or implementation-specific fixes that are too narrow to reuse beyond the triggering task or log.
- Exclude secrets, transient debugging notes, raw conversation logs, and task-local noise.
- Keep new or still-uncodified lessons in the pending table until they are codified or deliberately dropped.
- Add a new lesson by appending one new row to the pending table; do not regenerate, reorder, or rewrite unrelated rows.
- Preserve unrelated existing lessons, including local uncommitted ones already on disk.
- Only update or remove a specific lesson row when that same lesson is being codified, disproven, narrowed, or deduplicated.

## Pending Rules

| Date | Lesson | Status | Codification target |
| --- | --- | --- | --- |
| 2026-05-03 | Test fixtures should avoid ignored extensions such as `.log`; a local ignored fixture can make tests pass locally while CI fails from a clean checkout. | Pending | Terraform wrapper test guidance or fixture conventions |
| 2026-05-03 | `pull_request_target` PR validation uses the default-branch workflow configuration, so workflow fixes in the current PR do not repair that PR's own target-triggered check until the base branch has the fix. | Pending | GitHub Actions guidance |
| 2026-05-03 | When extracting an existing validation workflow into a local wrapper action, preserve current default validation semantics and make stricter policy such as scope allowlists opt-in unless the user explicitly requests the tighter gate. | Pending | GitHub Actions/composite action wrapper guidance |
| 2026-05-05 | In release workflows that mint a GitHub App token, keep the job-level `GITHUB_TOKEN` at no additional permissions and grant write access only to the minted App installation token. | Pending | GitHub Actions guidance |
| 2026-05-05 | Manual release workflows that can run on arbitrary branches should use a protected GitHub `environment` gate so `workflow_dispatch` does not mint high-privilege release credentials without reviewer control. | Pending | GitHub Actions guidance |
| 2026-05-05 | Repository-owned release wrapper actions should require release config and manifest paths to stay repository-relative and inside `GITHUB_WORKSPACE`; validating only that the file exists and is JSON is too weak for a privileged action contract. | Pending | Release wrapper guidance |
| 2026-05-05 | Before enabling auto-merge for a release PR, re-verify the PR through GitHub API/CLI data and enforce branch, author, state, and cross-repository checks instead of trusting upstream action outputs alone. | Pending | Release wrapper guidance |
| 2026-05-05 | In GitHub workflows, when secret-, var-, or context-derived values are reused across `with` or `run`, map them into step-local `env` first; this reduces direct expression-expansion warnings and keeps privileged values scoped to the steps that need them. | Pending | GitHub Actions guidance |
