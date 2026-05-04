# Release Please

Compatibility wrapper for [actions/global/release-please-google](../release-please-google/README.md).

## Status

- Existing internal workflows can keep using `actions/global/release`.
- The implementation now delegates to `actions/global/release-please-google`.
- Default consumer configuration now lives at the repository root:
  - `release-please-config.json`
  - `.release-please-manifest.json`

## Compatibility Notes

- `skip-github-release` and `skip-github-pull-request` are retained only as compatibility inputs.
- Both legacy skip inputs must remain `false`.
- New consumers should use `actions/global/release-please-google` directly.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `github-token` | Yes |  | Token used by `release-please` and `gh`. |
| `target-branch` | No |  | Target branch for release PRs. Empty falls back to `main`. |
| `config-file` | No | `release-please-config.json` | Release Please config path. |
| `manifest-file` | No | `.release-please-manifest.json` | Release Please manifest path. |
| `skip-github-release` | No | `false` | Legacy compatibility input. Must remain `false`. |
| `skip-github-pull-request` | No | `false` | Legacy compatibility input. Must remain `false`. |

## Outputs

| Output | Description |
| --- | --- |
| `releases-created` | True when at least one release was created. |
| `paths-released` | JSON array of released category paths. |
| `prs-created` | True when at least one Release PR was created or updated. |
| `prs` | Normalized JSON array with resolved Release PR metadata. |

## Usage

```yaml
steps:
  - uses: ./actions/global/release
    with:
      github-token: ${{ secrets.GITHUB_TOKEN }}
      target-branch: ${{ github.ref_name }}
      config-file: release-please-config.json
      manifest-file: .release-please-manifest.json
```

For new integrations, prefer `./actions/global/release-please-google` directly.
