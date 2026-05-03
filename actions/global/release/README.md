# Release Please

Creates independent category releases for `scripts`, `code`, and `actions` through `release-please` manifest mode.

## Behavior

- Creates or updates separate Release PRs per configured category.
- Publishes the category GitHub Release after the corresponding Release PR is merged.
- Uses component tags such as `scripts-v1.2.3`, `code-v1.2.3`, and `actions-v1.2.3`.
- Keeps release configuration and manifest state inside `actions/global/release/`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github-token` | Yes |  | Token used by `release-please`. |
| `target-branch` | No |  | Target branch for release PRs. Empty lets `release-please` detect it. |
| `config-file` | No | `actions/global/release/release-please-config.json` | Release Please config path. |
| `manifest-file` | No | `actions/global/release/.release-please-manifest.json` | Release Please manifest path. |
| `skip-github-release` | No | `false` | Skip publishing GitHub releases. |
| `skip-github-pull-request` | No | `false` | Skip creating or updating release PRs. |

## Outputs

| Output | Description |
| --- | --- |
| `releases-created` | True when at least one release was created. |
| `paths-released` | JSON array of released category paths. |
| `prs-created` | True when at least one Release PR was created or updated. |
| `prs` | JSON array with Release PR metadata. |

## Usage

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # actions/checkout@v6.0.2 release: https://github.com/actions/checkout/releases/tag/v6.0.2
    with:
      persist-credentials: false

  - uses: ./actions/global/release
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      target-branch: ${{ github.ref_name }}
```
