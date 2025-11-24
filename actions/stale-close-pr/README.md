# GitHub PR Auto Close Action

This action automatically marks pull requests as stale after a configurable period of inactivity and closes them if no further activity occurs.

## Features

- ✅ Automatically marks PRs as stale after a configurable number of days (default: 25 days)
- ✅ Automatically closes stale PRs after additional days of inactivity (default: 5 days)
- ✅ Fully configurable with sensible defaults
- ✅ Support for exemptions by labels, assignees, or authors
- ✅ Customizable messages for stale and close notifications
- ✅ Excludes draft PRs by default
- ✅ Removes stale label when PR is updated

## Usage

### Basic Usage

```yaml
name: Close Stale PRs
on:
  schedule:
    # Run daily at 1:00 AM UTC
    - cron: '0 1 * * *'
  workflow_dispatch: # Allow manual trigger

jobs:
  stale:
    runs-on: ubuntu-latest
    steps:
      - name: Close stale PRs
        uses: pagopa/eng-github-actions-iac-template/global/github-stale-close-pr@main
```

### Advanced Usage with Custom Configuration

```yaml
name: Close Stale PRs
on:
  schedule:
    - cron: '0 1 * * *'
  workflow_dispatch:

jobs:
  stale:
    runs-on: ubuntu-latest
    steps:
      - name: Close stale PRs
        uses: pagopa/eng-github-actions-iac-template/global/github-stale-close-pr@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          days-before-stale: 30
          days-before-close: 7
          stale-pr-label: 'inactive'
          exempt-pr-labels: 'keep-open,in-progress,blocked'
          exempt-draft-pr: 'true'
          stale-pr-message: |
            ⚠️ This PR has been inactive for 30 days and will be closed in 7 days.
            Please update if you want to keep it open.
          close-pr-message: |
            🔒 This PR has been automatically closed due to inactivity.
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `github-token` | GitHub token for authentication | No | `${{ github.token }}` |
| `days-before-stale` | Number of days of inactivity before a PR is marked as stale | No | `25` |
| `days-before-close` | Number of days of inactivity before a stale PR is closed | No | `5` |
| `stale-pr-label` | Label to apply to stale PRs | No | `stale` |
| `close-pr-label` | Label to apply when a PR is automatically closed | No | `auto-close` |
| `exempt-pr-labels` | Comma-separated list of labels that exempt a PR from being marked as stale | No | `''` |
| `exempt-pr-assignees` | Comma-separated list of assignees that exempt a PR from being marked as stale | No | `''` |
| `exempt-draft-pr` | Exempt draft PRs from being marked as stale | No | `true` |
| `stale-pr-message` | Message to post on PRs when they are marked as stale | No | See default message |
| `close-pr-message` | Message to post on PRs when they are closed | No | See default message |
| `operations-per-run` | Maximum number of operations per run (to avoid rate limits) | No | `30` |
| `remove-stale-when-updated` | Remove stale label when a PR is updated | No | `true` |
| `ascending` | Process PRs in ascending order (oldest first) | No | `false` |

## How It Works

1. **Detection**: The action runs on a schedule (typically daily) and checks for PRs that have been inactive
2. **Stale Marking**: After `days-before-stale` days of inactivity (default: 25 days), the PR is labeled with `stale-pr-label` and a warning comment is added
3. **Auto-Close**: If the stale PR remains inactive for `days-before-close` additional days (default: 5 days), it is automatically closed with a closing message and labeled with `close-pr-label`
4. **Branch Deletion**: When a PR is closed automatically, its associated branch is deleted
5. **Reactivation**: If activity occurs on a stale PR (new commit, comment, review), the stale label is automatically removed

## Examples

### Example 1: Conservative Settings (Longer Grace Period)

```yaml
- uses: pagopa/eng-github-actions-iac-template/global/github-stale-close-pr@main
  with:
    days-before-stale: 45
    days-before-close: 15
    exempt-pr-labels: 'priority,urgent,wip'
```

### Example 2: Aggressive Settings (Faster Cleanup)

```yaml
- uses: pagopa/eng-github-actions-iac-template/global/github-stale-close-pr@main
  with:
    days-before-stale: 14
    days-before-close: 3
    stale-pr-label: 'auto-close-pending'
    close-pr-label: 'closed-by-bot'
```

### Example 3: Only Label, Don't Close

```yaml
- uses: pagopa/eng-github-actions-iac-template/global/github-stale-close-pr@main
  with:
    days-before-stale: 30
    days-before-close: -1  # Never close, only mark as stale
```

### Example 4: Exempt Specific Labels

```yaml
- uses: pagopa/eng-github-actions-iac-template/global/github-stale-close-pr@main
  with:
    exempt-pr-labels: 'dependencies,keep-open,wip'
```

## Best Practices

1. **Schedule Frequency**: Run the action daily to ensure consistent monitoring
2. **Communication**: Use clear messages to inform contributors about the policy
3. **Exemptions**: Use labels like `keep-open` or `blocked` for PRs that need to stay open longer
4. **Testing**: Test with `workflow_dispatch` before setting up automated schedules
5. **Rate Limits**: Adjust `operations-per-run` if you have many PRs to avoid GitHub API rate limits

## Notes

- Draft PRs are excluded by default to allow work-in-progress contributions
- The action only processes PRs, not issues
- Stale labels are automatically removed when PRs receive new activity
- When a PR is closed automatically, the associated branch is deleted
- Closed PRs are labeled with `close-pr-label` (default: `auto-close`) for easy identification
- The action uses GitHub's official `actions/stale@v10` under the hood

## Troubleshooting

### PRs are not being marked as stale

- Verify the workflow is running (check Actions tab)
- Check if PRs have exempt labels
- Ensure the `github-token` has proper permissions

### Rate limit errors

- Reduce `operations-per-run` to a lower number
- Consider running less frequently

### Specific PRs should not be closed

- Add exempt labels to those PRs
- Add assignees to `exempt-pr-assignees`
- Enable draft mode for WIP PRs

## License

This action is part of the PagoPA engineering infrastructure templates.
