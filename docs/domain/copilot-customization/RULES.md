# Copilot Customization Rules

## COPILOT-001 Asset shape

- Rule ID: COPILOT-001
- Owner: Copilot Customization
- Severity: high
- Enforcement owner: `.github` customization validators and the repository pre-commit workflow
- Evidence: `.github/workflows/_code-analysis.yml`, `.github/workflows/_pre-commit.yml`, `.pre-commit-config.yaml`
- Remediation: Keep each customization asset in its declared file shape and run the repository validation workflow before release.
- Rule: Copilot customization assets must use the repository-supported instruction, agent, skill, prompt, or configuration shape expected by the validators.

## COPILOT-002 Validation profile

- Rule ID: COPILOT-002
- Owner: Copilot Customization
- Severity: high
- Enforcement owner: `.github/workflows/_code-analysis.yml`
- Evidence: `.github/workflows/_code-analysis.yml`, `.github/scripts/`
- Remediation: Run the strict customization and token-risk checks for the affected scope and resolve reported contract findings.
- Rule: Changes to Copilot customization must pass the repository's applicable validation profile before they are treated as ready for delivery.
