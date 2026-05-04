# Semantic Release

Run `cycjimmy/semantic-release-action` through an internal wrapper that generates `.releaserc.json` at runtime.

## Purpose

- Standardize direct release automation for private repositories on GitHub.com.
- Generate `.releaserc.json` internally so the consumer repository does not need to store it.
- Create tags, GitHub Releases, and a persistent `CHANGELOG.md`.
- Commit the updated changelog through `@semantic-release/git` with `[skip ci]` to avoid workflow loops.

## Which Release Wrapper Should I Use?

| Action | Use when |
| --- | --- |
| `release-please-google` | Monorepo, multiple products, separate changelogs, manifest-based releases, release PR review gate, optional auto-merge |
| `semantic-release` | Direct single release line, root changelog, no release PR, automatic tag and GitHub Release creation |

## When To Use It

- You want direct release publication from the target branch.
- You need one root `CHANGELOG.md` updated on every release.
- You do not want a consumer-owned `.releaserc.json` file.
- You want a generic or polyglot release flow without npm publishing by default.

## When Not To Use It

- You need separate release PRs and manual review gates before tagging.
- You need manifest-based monorepo releases with per-component changelogs.
- You want the cleanest possible release flow with no changelog commit back to the repository.
- You plan to mix this action with `release-please-google` in the same workflow without an explicit design reason.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github_token` | Yes |  | GitHub token used by `semantic-release`. It can be `GITHUB_TOKEN` or a GitHub App installation token. |
| `checkout` | No | `true` | Whether the wrapper performs `actions/checkout` internally with `fetch-depth: 0`. |
| `semantic_version` | No | `24.1.1` | `semantic-release` version installed by the upstream action. |
| `branches` | No | `[{"main"}]` equivalent JSON | JSON array of release branches. |
| `tag_format` | No | `v${version}` | Tag format passed to the generated config. |
| `preset` | No | `angular` | Conventional commit preset used by analyzer and notes generator. |
| `changelog_file` | No | `CHANGELOG.md` | Changelog path updated by the generated config. |
| `git_author_name` | No | `github-actions[bot]` | Git author name used by `@semantic-release/git`. |
| `git_author_email` | No | `41898282+github-actions[bot]@users.noreply.github.com` | Git author email used by `@semantic-release/git`. |
| `release_rules` | No | See `action.yml` | JSON array passed to `@semantic-release/commit-analyzer`. |
| `extra_plugins` | No | See `action.yml` | Additional plugins installed before `semantic-release` runs. |
| `debug` | No | `false` | Print the generated non-secret `.releaserc.json` content. |

## Generated Configuration

The wrapper generates a `.releaserc.json` equivalent to this shape:

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

## Important Behavior Note

Using `@semantic-release/changelog` together with `@semantic-release/git` means the release flow writes and commits `CHANGELOG.md` back to the repository.

This is less pure than a GitHub Release-notes-only flow, but it satisfies the requirement to keep a persistent changelog in the repository.

The generated git commit message contains `[skip ci]` to avoid CI loops on the changelog commit.

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

Default consumer permissions:

```yaml
permissions:
  contents: write
  issues: write
  pull-requests: write
```

If you customize the semantic-release GitHub plugin so it does not comment on issues or pull requests, you can reduce the permissions to:

```yaml
permissions:
  contents: write
```

## Basic Example

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
          github_token: ${{ secrets.RELEASE_GITHUB_APP_TOKEN }}
          branches: |
            ["main"]
          tag_format: v${version}
          changelog_file: CHANGELOG.md
```

## Example With GitHub App Token

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
        uses: actions/create-github-app-token@v2
        with:
          app-id: ${{ secrets.RELEASE_APP_ID }}
          private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

      - uses: pagopa/<repo-actions>/actions/global/semantic-release@<sha>
        with:
          github_token: ${{ steps.app-token.outputs.token }}
          branches: |
            ["main"]
          changelog_file: CHANGELOG.md
          debug: "true"
```

The wrapper does not create the GitHub App token internally. Token generation remains the responsibility of the consumer workflow.

## Risks And Trade-Offs

- The wrapper updates and commits `CHANGELOG.md`, which changes repository history during the release flow.
- Protected branches may require a GitHub App token instead of the default `GITHUB_TOKEN`.
- The generated config is intentionally generic and does not include language-specific publish plugins.
- The wrapper does not run npm publishing because the generated config does not include `@semantic-release/npm`.

## Troubleshooting

### `branches must be valid JSON`

- Ensure the `branches` input is a valid JSON array.
- Avoid YAML fragments or JavaScript expressions in that input.

### `release_rules must be valid JSON`

- Ensure the `release_rules` input is a valid JSON array.
- Keep custom release rules compact and machine-readable.

### Protected branch push failures

- Use `persist-credentials: false` on checkout, which this wrapper already does.
- Prefer a GitHub App installation token when branch protection prevents the default `GITHUB_TOKEN` from pushing the changelog commit.

### Missing changelog updates

- Confirm the commit history follows Conventional Commits.
- Confirm the generated config points to the intended `changelog_file`.
- Enable `debug: "true"` to inspect the generated `.releaserc.json` content in workflow logs.

## Pinning Notes

- Third-party actions inside this wrapper are pinned to full commit SHAs.
- Consumer workflows should pin this internal wrapper action with a full commit SHA before production usage.
