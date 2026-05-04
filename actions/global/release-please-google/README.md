# Release Please Google

Run `googleapis/release-please-action` in manifest mode through an internal enterprise wrapper.

## Purpose

- Standardize `release-please` usage for private repositories on GitHub.com.
- Read release configuration from consumer-owned JSON files instead of inline YAML.
- Optionally enable conservative auto-merge on release PRs with `gh pr merge --auto`.
- Keep third-party action pinning inside the wrapper.

## Which Release Wrapper Should I Use?

| Action | Use when |
| --- | --- |
| `release-please-google` | Monorepo, multiple products, separate changelogs, manifest-based releases, release PR review gate, optional auto-merge |
| `semantic-release` | Direct single release line, root changelog, no release PR, automatic tag and GitHub Release creation |

## When To Use It

- You need a manifest-driven release flow.
- You need separate release PRs per component or path.
- You want release PRs to stay reviewable before merge.
- You want optional PR auto-merge after branch protection checks succeed.

## When Not To Use It

- You want direct releases without a release PR.
- You need a single root changelog only and no manifest file.
- You want the wrapper to generate release configuration automatically.
- You plan to mix this action with `semantic-release` in the same workflow run.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github_token` | Yes |  | GitHub token used by `release-please` and `gh`. It can be `GITHUB_TOKEN` or a GitHub App installation token. |
| `checkout` | No | `true` | Whether the wrapper performs `actions/checkout` internally with `fetch-depth: 0`. |
| `target_branch` | No | `main` | Target branch for release PRs. |
| `config_file` | No | `release-please-config.json` | Repository-relative path to the release-please config file. |
| `manifest_file` | No | `.release-please-manifest.json` | Repository-relative path to the release-please manifest file. |
| `auto_merge` | No | `true` | Enable conservative auto-merge on resolved release PRs. |
| `merge_method` | No | `squash` | Auto-merge method. Allowed values: `merge`, `squash`, `rebase`. |
| `debug` | No | `false` | Print non-secret diagnostic information. |

## Outputs

| Output | Description |
| --- | --- |
| `release_created` | `true` when any release was created. |
| `pr` | First resolved release PR URL, when available. |
| `prs` | Normalized JSON array of resolved release PRs, when available. |
| `tag_name` | Root tag created by `release-please`, when available. |
| `config_file` | Config file path used by the wrapper. |
| `manifest_file` | Manifest file path used by the wrapper. |
| `auto_merge_enabled` | `true` when auto-merge was requested, `false` otherwise. |
| `releases_created` | Raw `release-please` any-release output. |
| `paths_released` | Raw `release-please` released-paths JSON. |
| `prs_created` | Raw `release-please` PR-created flag. |

## Minimum Permissions

```yaml
permissions:
  contents: write
  pull-requests: write
```

The wrapper sets `skip-labeling: true` on the upstream action so the consumer workflow can stay on the narrower permission set above.

## Basic Example

```yaml
name: Release Please

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: pagopa/<repo-actions>/actions/global/release-please-google@<sha>
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          target_branch: main
          config_file: release-please-config.json
          manifest_file: .release-please-manifest.json
          auto_merge: "true"
          merge_method: squash
```

## Example With GitHub App Token

```yaml
name: Release Please

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Mint GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - uses: pagopa/<repo-actions>/actions/global/release-please-google@<sha>
        with:
          github_token: ${{ steps.app-token.outputs.token }}
          target_branch: main
```

The wrapper does not create the GitHub App token internally. Token generation remains the responsibility of the consumer workflow.

## Consumer Configuration Files

Default file names:

- `release-please-config.json`
- `.release-please-manifest.json`

Example `release-please-config.json`:

```json
{
  "release-type": "simple",
  "separate-pull-requests": false,
  "include-component-in-tag": true,
  "packages": {
    "apps/service-a": {
      "component": "service-a",
      "changelog-path": "CHANGELOG.md"
    },
    "apps/service-b": {
      "component": "service-b",
      "changelog-path": "CHANGELOG.md"
    }
  }
}
```

Example `.release-please-manifest.json`:

```json
{
  "apps/service-a": "1.0.0",
  "apps/service-b": "1.0.0"
}
```

## Auto-Merge Behavior

- The wrapper prefers the upstream `pr` and `prs` outputs when they are present.
- If those outputs are missing, it falls back to `gh pr list` and filters conservatively.
- The fallback only considers PRs that match all of these conditions:
  - open PR against `target_branch`
  - head branch starts with `release-please--`
  - title contains `chore: release`
  - author login looks like a bot or GitHub App identity
- Auto-merge uses `gh pr merge --auto` with the requested merge method.
- The wrapper never performs a direct blind merge command.

## Risks And Trade-Offs

- Auto-merge still depends on repository-level auto-merge being enabled.
- If multiple legitimate release PRs exist, the wrapper enables auto-merge on each resolved release-please PR.
- Root `tag_name` is only populated when `release-please` emits a root release output.
- Consumer-owned JSON files remain the source of truth, which is flexible but requires repository discipline.

## Troubleshooting

### `release-please config file not found`

- Ensure the workflow checked out the repository, either externally or through `checkout: "true"`.
- Ensure `config_file` points to a file committed in the consumer repository.

### `release-please manifest file not found`

- Ensure `manifest_file` exists and is valid JSON.
- Ensure the path is repository-relative.

### `No open release-please pull request was found`

- Check whether the commit history actually triggered a release PR update.
- Check whether the PR title and branch still match release-please conventions.
- If the PR was created but upstream outputs are empty, enable `debug: "true"` and inspect the fallback diagnostics.

### `Repository auto-merge is not enabled`

- Enable auto-merge in repository settings before using `auto_merge: "true"`.
- Confirm the target branch protection rules allow auto-merge.

### `github_token does not have enough permissions`

- Ensure the token can write contents and pull requests.
- If branch protection requires elevated permissions, use a GitHub App installation token instead of the default `GITHUB_TOKEN`.

## Pinning Notes

- Third-party actions inside this wrapper are pinned to full commit SHAs.
- Consumer workflows should pin this internal wrapper action with a full commit SHA before production usage.
