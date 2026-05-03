# Semantic PR Title

Validates pull request titles with Conventional Commit semantics through a local wrapper around `amannn/action-semantic-pull-request`.

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

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # actions/checkout@v6.0.2 release: https://github.com/actions/checkout/releases/tag/v6.0.2
    with:
      persist-credentials: false

  - uses: ./actions/global/pr-title
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```
