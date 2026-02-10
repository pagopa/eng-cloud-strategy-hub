# AGENTS.md - eng-cloud-strategy-hub

This file is the bridge for Codex/Copilot behavior in this repository.

## Main Instructions
- Read .github/copilot-instructions.md first.
- Apply relevant files under .github/instructions/.
- Use this file as an index only; do not duplicate or override policies already defined in .github/.

## Configuration Baseline
- .github/copilot-instructions.md
- .github/copilot-code-review-instructions.md
- .github/copilot-commit-message-instructions.md
- .github/security-baseline.md
- .github/DEPRECATION.md
- .github/repo-profiles.yml
- .github/README.md
- .github/dependabot.yml

## Recommended Profile
- infrastructure-heavy from .github/repo-profiles.yml

## Available Skills (Local)
- .github/skills/cloud-policy/SKILL.md: Create or modify governance policies for AWS SCP, Azure Policy, and GCP Org Policy.
- .github/skills/terraform-feature/SKILL.md: Add or modify Terraform resources, variables, outputs, and data sources.
- .github/skills/terraform-module/SKILL.md: Create or modify reusable Terraform modules with standard file layout and validation.

## Available Prompts (Local)
- .github/prompts/cs-cloud-policy.prompt.md
- .github/prompts/cs-terraform.prompt.md

## Validation Commands
- .github/scripts/validate-copilot-customizations.sh --scope repo=eng-cloud-strategy-hub --mode legacy-compatible
- terraform fmt -check
- terraform validate
- bash -n .github/scripts/*.sh
- shellcheck -s bash .github/scripts/*.sh (if available)
- pytest -q (when Python logic changes)

## Prohibitions
- Never commit secrets, tokens, credentials, or plaintext keys.
- Do not weaken least-privilege controls for IAM, repository access, or workflow permissions.
- Do not introduce unpinned third-party GitHub Actions.
- Do not remove required PR checks for changes under .github/**.
