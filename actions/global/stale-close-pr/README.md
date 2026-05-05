# GitHub PR Auto Close

Marks inactive pull requests as stale and optionally closes them after an additional inactivity window.

## Self-Contained Contract

- This action manages only pull request stale and close behavior.
- It does not checkout code and does not call or require any other action under `actions/global`.
- It prepares default comments locally, then delegates stale processing to `actions/stale`.
- It disables issue processing by setting issue stale and close windows to `-1`.

## Behavior

- Marks inactive PRs after `days-before-stale`.
- Closes stale PRs after `days-before-close`, unless that value is `-1`.
- Exempts draft PRs by default.
- Supports exemption labels and assignees.
- Removes the stale label when activity resumes by default.
- Can delete the source branch after auto-close when `delete-branch` is `"true"`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github-token` | No | `${{ github.token }}` | Token used by `actions/stale`. Empty input falls back to the workflow token. |
| `days-before-stale` | No | `25` | Days of PR inactivity before applying `stale-pr-label`. Use `-1` to disable stale marking. |
| `days-before-close` | No | `5` | Additional days before closing a stale PR. Use `-1` to mark stale without closing. |
| `stale-pr-label` | No | `stale` | Label applied when a PR becomes stale. |
| `close-pr-label` | No | `auto-close` | Label applied when a PR is automatically closed. |
| `exempt-pr-labels` | No |  | Comma-separated labels that exempt a PR. |
| `exempt-pr-assignees` | No |  | Comma-separated assignees that exempt a PR. |
| `exempt-draft-pr` | No | `true` | Exempt draft PRs. |
| `stale-pr-message` | No | Generated | Comment posted when a PR becomes stale. Empty input uses the generated message. |
| `close-pr-message` | No | Generated | Comment posted when a PR is closed. Empty input uses the generated message. |
| `operations-per-run` | No | `30` | Maximum stale operations per run. |
| `remove-stale-when-updated` | No | `true` | Remove the stale label after new activity. |
| `ascending` | No | `false` | Process older PRs first when `"true"`. |
| `delete-branch` | No | `false` | Delete the PR branch after auto-close. |

## Minimum Permissions

```yaml
permissions:
  contents: read
  pull-requests: write
  issues: write
```

`issues: write` is needed because GitHub pull request comments use the issues API.
Keep `contents: read` for the default `delete-branch: "false"` behavior. Set
`contents: write` when using `delete-branch: "true"` because `actions/stale`
needs write access to delete the source branch after closing the PR.

## Usage

### Basic With Defaults Shown

```yaml
name: Stale PR Sweeper

on:
  schedule:
    - cron: '0 1 * * *'
  workflow_dispatch:

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  stale-prs:
    runs-on: ubuntu-latest
    steps:
      - uses: pagopa/<repo-actions>/actions/global/stale-close-pr@<sha>
        with:
          github-token: ${{ github.token }}
          days-before-stale: "25"
          days-before-close: "5"
          stale-pr-label: stale
          close-pr-label: auto-close
          exempt-pr-labels: ""
          exempt-pr-assignees: ""
          exempt-draft-pr: "true"
          stale-pr-message: ""
          close-pr-message: ""
          operations-per-run: "30"
          remove-stale-when-updated: "true"
          ascending: "false"
          delete-branch: "false"
```

### Mark Only, Do Not Close

```yaml
steps:
  - uses: pagopa/<repo-actions>/actions/global/stale-close-pr@<sha>
    with:
      days-before-stale: "30"
      days-before-close: "-1"
      exempt-pr-labels: keep-open,blocked
```

### Custom Messages

```yaml
steps:
  - uses: pagopa/<repo-actions>/actions/global/stale-close-pr@<sha>
    with:
      days-before-stale: "45"
      days-before-close: "10"
      stale-pr-message: |
        This PR has been inactive for 45 days.
        Please comment or push commits if it should stay open.
      close-pr-message: |
        This PR was closed after the stale grace period expired.
```

## How It Works

1. The wrapper validates numeric and boolean inputs.
2. The wrapper generates stale and close messages when custom messages are empty.
3. `actions/stale` applies labels, comments, stale removal, close behavior, and optional branch deletion.
4. Issue processing stays disabled; only pull requests are processed.

## Troubleshooting

### PRs are not marked stale

- Confirm the schedule or manual run actually executed.
- Check `exempt-pr-labels`, `exempt-pr-assignees`, and draft status.
- Confirm the workflow token has `pull-requests: write` and `issues: write`.

### Boolean input rejected

- Use exact string values: `"true"` or `"false"`.

### Too many operations in one run

- Lower `operations-per-run`.
- Run the workflow more frequently if the repository has many open PRs.
