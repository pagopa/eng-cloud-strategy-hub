# Reusable Automation

This context names the repository-owned language for composite actions, their callers, and release automation.

## Language

**Composite action**:
A reusable GitHub Actions unit that exposes inputs, outputs, and ordered execution steps.
_Avoid_: Workflow, script

**Caller workflow**:
A GitHub Actions workflow that supplies the execution context and permissions for a composite action.
_Avoid_: Consumer action

**Code-analysis workflow**:
The repository workflow for static analysis and Copilot entrypoint smoke tests.
_Avoid_: Caller workflow, validation profile

**Release PR**:
A pull request opened or updated by release automation so release changes can be reviewed before publication.
_Avoid_: Deployment PR, release commit

**Release publication**:
The creation of a version tag and GitHub Release after the release process completes.
_Avoid_: Release PR
