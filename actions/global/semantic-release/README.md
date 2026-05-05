# Semantic Release

Runs `cycjimmy/semantic-release-action` through a repository-owned composite action that generates `.releaserc.json` at runtime.

## Self-Contained Contract

- This action owns one direct semantic-release workflow contract end to end.
- It does not call or require any other action under `actions/global`.
- The consumer repository does not need to store `.releaserc.json`.
- Third-party actions used by the wrapper are pinned inside `action.yml`.

## When To Use It

- You want direct release publication from the target branch.
- You need one root changelog file updated on release.
- You want tags and GitHub Releases generated from Conventional Commits.
- You do not need a release PR review gate before publishing.

## Behavior

1. Validates scalar wrapper inputs.
2. Optionally checks out the repository with full history, but skips that internal checkout when the caller workspace already contains a non-shallow Git clone.
3. Generates `.releaserc.json` from action inputs with a local Python script.
4. Runs `cycjimmy/semantic-release-action`.
5. Forwards semantic-release outputs to the caller.

The generated config uses `@semantic-release/changelog` and `@semantic-release/git`, so successful releases commit the updated changelog back to the repository. The generated git commit message includes `[skip ci]`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github_token` | Yes |  | Token used by `semantic-release`. It can be `GITHUB_TOKEN` or a GitHub App installation token. |
| `checkout` | No | `true` | Whether the wrapper may run `actions/checkout` internally with `fetch-depth: 0`. The wrapper skips that internal checkout when the caller workspace is already a full, non-shallow Git clone. |
| `semantic_version` | No | `24.1.1` | `semantic-release` version installed by the upstream action. |
| `branches` | No | `["main"]` | JSON array of release branches. |
| `tag_format` | No | `v${version}` | Tag format written to the generated config. |
| `preset` | No | `angular` | Conventional commit preset for analyzer and notes generator. |
| `changelog_file` | No | `CHANGELOG.md` | Changelog path updated by the generated config. |
| `git_author_name` | No | `github-actions[bot]` | Git author and committer name. |
| `git_author_email` | No | `41898282+github-actions[bot]@users.noreply.github.com` | Git author and committer email. |
| `release_rules` | No | See `action.yml` | JSON array passed to `@semantic-release/commit-analyzer`. |
| `extra_plugins` | No | See `action.yml` | Plugins installed by the upstream action before execution. |
| `debug` | No | `false` | Print generated non-secret `.releaserc.json`. |

## Outputs

| Output | Description |
| --- | --- |
| `new_release_published` | Whether a new release was published. |
| `new_release_version` | New release version. |
| `new_release_major_version` | New release major version. |
| `new_release_minor_version` | New release minor version. |
| `new_release_patch_version` | New release patch version. |
| `new_release_git_head` | Git SHA for the new release. |
| `new_release_git_tag` | Git tag for the new release. |
| `last_release_version` | Previous release version, if any. |
| `last_release_git_head` | Previous release git SHA, if any. |
| `last_release_git_tag` | Previous release git tag, if any. |

## Minimum Permissions

Default permissions:

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
```

If your semantic-release GitHub plugin configuration never comments on issues or pull requests, the caller can reduce permissions to:

```yaml
permissions:
  contents: write
```

## Usage

### Basic With Defaults Shown

```yaml
name: Semantic Release

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: pagopa/<repo-actions>/actions/global/semantic-release@<sha>
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          checkout: "true"
          semantic_version: 24.1.1
          branches: |
            ["main"]
          tag_format: v${version}
          preset: angular
          changelog_file: CHANGELOG.md
          git_author_name: github-actions[bot]
          git_author_email: 41898282+github-actions[bot]@users.noreply.github.com
          release_rules: |
            [
              {"type": "breaking", "release": "major"}
            ]
          extra_plugins: |
            @semantic-release/commit-analyzer@13.0.1
            @semantic-release/release-notes-generator@14.0.3
            @semantic-release/changelog@6.0.3
            @semantic-release/git@10.0.1
            @semantic-release/github@11.0.1
          debug: "false"
```

### With GitHub App Token

```yaml
name: Semantic Release

on:
  push:
    branches:
      - main
  workflow_dispatch:

permissions:
  contents: write
  issues: write
  pull-requests: write

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - name: Mint GitHub App token
        id: app-token
        uses: actions/create-github-app-token@<sha>
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - uses: pagopa/<repo-actions>/actions/global/semantic-release@<sha>
        with:
          github_token: ${{ steps.app-token.outputs.token }}
          debug: "true"
```

The wrapper does not create the GitHub App token internally. Token creation remains the caller workflow's responsibility.

## Generated Configuration

The wrapper generates this config shape:

```json
{
  "branches": ["main"],
  "tagFormat": "v${version}",
  "plugins": [
    [
      "@semantic-release/commit-analyzer",
      {
        "preset": "angular",
        "releaseRules": [
          { "type": "breaking", "release": "major" }
        ]
      }
    ],
    [
      "@semantic-release/release-notes-generator",
      {
        "preset": "angular"
      }
    ],
    [
      "@semantic-release/changelog",
      {
        "changelogFile": "CHANGELOG.md"
      }
    ],
    [
      "@semantic-release/git",
      {
        "assets": ["CHANGELOG.md"],
        "message": "chore(release): ${nextRelease.version} [skip ci]\n\n${nextRelease.notes}"
      }
    ],
    "@semantic-release/github"
  ]
}
```

## Troubleshooting

### `branches must be valid JSON`

- Pass a JSON array, not YAML list syntax.
- Keep branch objects or strings valid for `semantic-release`.

### `release_rules must be valid JSON`

- Pass a JSON array.
- Avoid JavaScript comments or trailing commas.

### Protected branch push failures

- Keep `checkout: "true"` or checkout with `persist-credentials: false`.
- If the caller already checked out a full, non-shallow clone, the wrapper skips its internal checkout automatically.
- Prefer a GitHub App installation token when branch protection blocks `GITHUB_TOKEN` pushes.

### Missing changelog updates

- Confirm commits follow Conventional Commits.
- Confirm `changelog_file` points to the intended path.
- Enable `debug: "true"` to inspect the generated non-secret config.

## Pinning Notes

- Third-party actions inside this wrapper are pinned to full commit SHAs.
- Consumer workflows should pin this wrapper action with a full commit SHA before production usage.
