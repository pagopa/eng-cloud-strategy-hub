# Semantic PR Title

Validates pull request titles with Conventional Commit semantics through a local wrapper around `amannn/action-semantic-pull-request`.

## Self-Contained Contract

- This action validates only the pull request title contract.
- It does not checkout code and does not call or require any other action under `actions/global`.
- It validates wrapper booleans before delegating to the upstream title validator.
- It forwards the parsed title fields and upstream error message as action outputs.

## Behavior

- Reads the pull request title from the GitHub event context used by the upstream action.
- Accepts an optional type allowlist and optional scope allowlist.
- Allows any scope when `scopes` is empty.
- Can optionally validate the single commit message for one-commit PRs.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github-token` | Yes |  | Token used by the upstream validation action. |
| `types` | No | See `action.yml` | Allowed Conventional Commit types. |
| `scopes` | No |  | Optional scope allowlist. Empty allows any scope. |
| `require-scope` | No | `false` | Require a scope in every PR title. |
| `subject-pattern` | No | `.+` | Regex that the subject must match. |
| `subject-pattern-error` | No | `The pull request title subject must not be empty.` | Custom subject validation error. |
| `validate-single-commit` | No | `false` | Validate single-commit PR commit messages. |
| `validate-single-commit-matches-pr-title` | No | `false` | Require single commit message and PR title to match. |

## Outputs

| Output | Description |
| --- | --- |
| `type` | Parsed Conventional Commit type. |
| `scope` | Parsed Conventional Commit scope. |
| `subject` | Parsed Conventional Commit subject. |
| `error-message` | Upstream validation error message. |

## Usage

### Basic With Defaults Shown

```yaml
name: Validate PR Title

on:
  pull_request_target:
    types:
      - opened
      - edited
      - synchronize

permissions:
  contents: read
  pull-requests: read

jobs:
  title:
    runs-on: ubuntu-latest
    steps:
      - uses: pagopa/<repo-actions>/actions/global/pr-title@<sha>
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          types: |
            feat
            fix
            docs
            chore
            ci
            build
            refactor
            perf
            test
            revert
            breaking
          scopes: ""
          require-scope: "false"
          subject-pattern: .+
          subject-pattern-error: The pull request title subject must not be empty.
          validate-single-commit: "false"
          validate-single-commit-matches-pr-title: "false"
```

### Require Scopes

```yaml
steps:
  - uses: pagopa/<repo-actions>/actions/global/pr-title@<sha>
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      scopes: |
        actions
        docs
        terraform
      require-scope: "true"
```

## Troubleshooting

### Boolean input rejected

- Use the exact strings `"true"` or `"false"`.
- Do not pass YAML booleans when reviewing examples for portability.

### A valid-looking title fails

- Confirm the type is present in `types`.
- Confirm the scope is present in `scopes` when `scopes` is not empty.
