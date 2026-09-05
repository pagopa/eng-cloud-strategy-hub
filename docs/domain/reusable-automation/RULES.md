# Reusable Automation Rules

## AUTOMATION-001 Action interface

- Rule ID: AUTOMATION-001
- Owner: Reusable Automation
- Severity: high
- Enforcement owner: GitHub Actions workflow validation and the action-specific test suite
- Evidence: `actions/`, `tests/actions/`, `.github/workflows/_code-analysis.yml`
- Remediation: Keep action inputs and outputs explicit, update the focused tests, and rerun workflow validation.
- Rule: A reusable action must expose the inputs and outputs required by its callers and preserve the ordered execution contract verified by the repository tests.

## AUTOMATION-002 Release contract

- Rule ID: AUTOMATION-002
- Owner: Reusable Automation
- Severity: medium
- Enforcement owner: `.github/workflows/release.yml` and release configuration
- Evidence: `.github/workflows/release.yml`, `release-please-config.json`, `.release-please-manifest.json`
- Remediation: Route release changes through the configured release workflow and verify the generated tag and release metadata.
- Rule: Release publication must be performed by the repository release process after the release pull request and configured validation steps complete.
