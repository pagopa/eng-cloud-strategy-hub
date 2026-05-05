# Release Please Google

Runs `googleapis/release-please-action` in manifest mode through a repository-owned composite action.

## Self-Contained Contract

- This action owns one release-please workflow contract end to end.
- It does not call or require any other action under `actions/global`.
- Consumer release configuration remains in JSON files committed to the consumer repository.
- Third-party actions used by the wrapper are pinned inside `action.yml`.

## When To Use It

- You need manifest-driven releases.
- You need release PRs that can be reviewed before tags and GitHub Releases are created.
- You need one or more package paths in `release-please-config.json`.
- You want optional GitHub auto-merge on release PRs after branch protection checks pass.

## Behavior

1. Validates scalar wrapper inputs.
2. Optionally checks out the repository with full history, but skips that internal checkout when the caller workspace already contains a non-shallow Git clone.
3. Validates that `config_file` and `manifest_file` exist and contain valid JSON.
4. Runs `googleapis/release-please-action`. Labeling is left enabled so the action can recognize its own merged release PR (`autorelease: pending` / `autorelease: tagged`) and create the GitHub Release and tags on the next run.
5. Resolves release PRs from upstream outputs, then falls back to `gh pr list` when needed.
6. Enables auto-merge on resolved release PRs when `auto_merge` is `"true"`.
7. Requests deletion of the release PR branch when GitHub completes the merge.

When `release-please` creates a release, no open release PR is expected; the wrapper emits empty PR outputs and exits successfully.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github_token` | Yes |  | Token used by `release-please` and `gh`. It can be `GITHUB_TOKEN` or a GitHub App installation token. |
| `checkout` | No | `true` | Whether the wrapper may run `actions/checkout` internally with `fetch-depth: 0`. The wrapper skips that internal checkout when the caller workspace is already a full, non-shallow Git clone. |
| `target_branch` | No | `main` | Target branch for release PRs. |
| `config_file` | No | `release-please-config.json` | Repository-relative release-please config path. |
| `manifest_file` | No | `.release-please-manifest.json` | Repository-relative release-please manifest path. |
| `auto_merge` | No | `true` | Enable GitHub auto-merge on resolved release PRs. |
| `merge_method` | No | `squash` | Auto-merge method. Allowed values: `merge`, `squash`, `rebase`. |
| `debug` | No | `false` | Print non-secret diagnostics. |

## Outputs

| Output | Description |
| --- | --- |
| `release_created` | `true` when at least one release was created. |
| `pr` | First resolved release PR URL, when available. |
| `prs` | Normalized JSON array of resolved release PRs. |
| `tag_name` | Created root tag, when the upstream action emits one. |
| `config_file` | Config file path used by the wrapper. |
| `manifest_file` | Manifest file path used by the wrapper. |
| `auto_merge_enabled` | Mirrors the requested `auto_merge` input. |
| `releases_created` | Raw upstream any-release output. |
| `paths_released` | Raw upstream released-paths JSON. |
| `prs_created` | Raw upstream PR-created flag. |

## Minimum Permissions

```yaml
permissions: {}
```

The wrapper relies on release-please labels (`autorelease: pending`, `autorelease: tagged`) to detect already-merged release PRs and avoid release loops, so the GitHub App installation token must include `issues: write` in addition to `contents: write` and `pull-requests: write`.
The caller should grant write access only to the minted GitHub App installation token:

```yaml
- uses: actions/create-github-app-token@<sha>
  with:
    permission-contents: write
    permission-pull-requests: write
    permission-issues: write
```

## Force-release trigger

When release-please does not open a release PR (for example after a recovery, or when only non-conventional commits landed) you can force a release for a specific package by editing a tiny dummy file inside that package path and committing with a conventional commit.

The convention used in this repository: each package owns a `<package>/.release-trigger` file. Bump the counter inside it and commit, e.g.:

```bash
# Force a release for the `actions` package
sed -i '' 's/counter: \([0-9][0-9]*\)/counter: \1+1/' actions/.release-trigger # or just bump manually
git commit -am "fix(actions): force release"
git push
```

release-please will see a new commit affecting `actions/`, open a release PR, and bump the patch version on the next run. Use `feat(scope):` to bump the minor version instead.

## Usage

### Basic With Defaults Shown

```yaml
name: Release Please

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions: {}

jobs:
  release:
    runs-on: ubuntu-latest
    environment:
      name: release-manual
    steps:
      - name: Mint GitHub App token
        id: app-token
        uses: actions/create-github-app-token@<sha>
        env:
          RELEASE_APP_CLIENT_ID: ${{ vars.RELEASE_APP_CLIENT_ID }}
          RELEASE_APP_PRIVATE_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
        with:
          client-id: ${{ env.RELEASE_APP_CLIENT_ID }}
          private-key: ${{ env.RELEASE_APP_PRIVATE_KEY }}
          permission-contents: write
          permission-pull-requests: write
          permission-issues: write

      - uses: pagopa/<repo-actions>/actions/global/release-please-google@<sha>
        env:
          RELEASE_APP_TOKEN: ${{ steps.app-token.outputs.token }}
        with:
          github_token: ${{ env.RELEASE_APP_TOKEN }}
          checkout: "true"
          target_branch: main
          config_file: release-please-config.json
          manifest_file: .release-please-manifest.json
          auto_merge: "true"
          merge_method: squash
          debug: "false"
```

### With GitHub App Token

```yaml
name: Release Please

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions: {}

jobs:
  release:
    runs-on: ubuntu-latest
    environment:
      name: release-manual
    steps:
      - name: Mint GitHub App token
        id: app-token
        uses: actions/create-github-app-token@<sha>
        env:
          RELEASE_APP_CLIENT_ID: ${{ vars.RELEASE_APP_CLIENT_ID }}
          RELEASE_APP_PRIVATE_KEY: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}
        with:
          client-id: ${{ env.RELEASE_APP_CLIENT_ID }}
          private-key: ${{ env.RELEASE_APP_PRIVATE_KEY }}
          permission-contents: write
          permission-pull-requests: write
          permission-issues: write

      - uses: pagopa/<repo-actions>/actions/global/release-please-google@<sha>
        env:
          RELEASE_APP_TOKEN: ${{ steps.app-token.outputs.token }}
        with:
          github_token: ${{ env.RELEASE_APP_TOKEN }}
          target_branch: main
```

The wrapper does not create the GitHub App token internally. Token creation remains the caller workflow's responsibility.

## Consumer Configuration Files

Default file names:

- `release-please-config.json`
- `.release-please-manifest.json`

Both files must be repository-relative paths that resolve inside `GITHUB_WORKSPACE`.

Example `release-please-config.json`:

```json
{
  "release-type": "simple",
  "separate-pull-requests": false,
  "include-component-in-tag": true,
  "include-v-in-tag": true,
  "group-pull-request-title-pattern": "chore: release-please generated ${branch}",
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

## Auto-Merge Details

- The wrapper prefers upstream `pr` and `prs` outputs.
- Every candidate PR is verified with `gh pr view` before auto-merge is enabled.
- If those outputs are empty, it uses `gh pr list` and keeps only conservative release-please candidates:
  - open PR against `target_branch`
  - head branch starts with `release-please--`
  - title contains `chore: release`
  - author looks like a bot or GitHub App identity
- Auto-merge uses `gh pr merge --auto` with the requested merge method.
- Auto-merge passes `--delete-branch`, so GitHub deletes the remote release branch after the PR is merged.
- The wrapper does not perform a direct blind merge.
- If a release PR has merge conflicts, the wrapper keeps the PR open, logs a warning, and continues with the other release PRs.
- If GitHub reports that auto-merge is unavailable for a release PR, the wrapper keeps the PR open, logs a warning, and continues with the other release PRs.

## Troubleshooting

### `release-please config file not found`

- Keep `checkout: "true"` or checkout the repository before this action.
- If the caller already checked out a full, non-shallow clone, the wrapper skips its internal checkout automatically.
- Ensure `config_file` points to a committed JSON file.

### `release-please manifest file must be valid JSON`

- Ensure the manifest contains JSON object syntax.
- Do not use YAML or JavaScript comments in the manifest file.

### `No open release-please pull request was found`

- Confirm commits on `target_branch` actually trigger a release PR.
- Enable `debug: "true"` to print non-secret PR resolution diagnostics.
- If a release was created in the same run, no open release PR is expected.

### `The permissions requested are not granted to this installation`

- The failure happens before `release-please` starts: `actions/create-github-app-token` asked GitHub for a scoped installation token that includes a permission the app installation does not currently have.
- For this wrapper the required installation permissions are `contents: write`, `pull-requests: write`, and `issues: write`.
- Update the GitHub App repository permissions and then approve the new permission on the existing installation for the target repository or organization.
- If the app settings were already updated, re-check the installation approval page: GitHub Apps can expose a permission in app settings before that permission is granted on an older installation.

### `Repository auto-merge is not enabled`

- The wrapper leaves the release PR open and continues, but auto-merge is not enabled for that PR.
- Enable auto-merge in repository settings.
- Confirm the target branch has the required protected branch rules for the selected method.

### `Pull Request has merge conflicts`

- release-please created or updated the PR correctly, but GitHub cannot enable auto-merge until the conflict is resolved.
- Rebase or merge the release branch against the target branch, or close and regenerate the conflicting release PR if that is simpler for the branch state.

## Pinning Notes

- Third-party actions inside this wrapper are pinned to full commit SHAs.
- Consumer workflows should pin this wrapper action with a full commit SHA before production usage.
