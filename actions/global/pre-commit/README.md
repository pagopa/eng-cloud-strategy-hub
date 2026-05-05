# Pre-commit Container Runner

Runs repository `pre-commit` checks inside the pinned `pre-commit-terraform` container image.

## Self-Contained Contract

- This action only runs `pre-commit` in a container against the current workspace.
- It does not call or require any other action under `actions/global`.
- The caller must checkout the repository before invoking this action.
- Cache restore/save remains the caller workflow's responsibility.

## Behavior

- Validates that the container image is pinned by digest.
- Validates that `pre-commit-config` exists in the workspace.
- Resolves an empty `pre-commit-cache-dir` to `$RUNNER_TEMP/pre-commit-cache`.
- Uses `PRE_COMMIT_HOME` mounted from a caller-provided cache directory.
- Pulls the configured image and prints the bundled tool versions before running checks.
- Sets `TF_INPUT=0` and `TF_IN_AUTOMATION=1` for Terraform hooks.
- Passes `run-args` to `pre-commit run` before adding `--config`.

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `pre-commit-image` | No | `ghcr.io/antonbabenko/pre-commit-terraform:v1.105.0@sha256:4ef4b8323b27fc263535ad88c9d2f20488fcb3b520258e5e7f0553ed5f6692b5` | Digest-pinned container image. |
| `pre-commit-config` | No | `.pre-commit-config.yaml` | Path to the pre-commit config file. |
| `pre-commit-cache-dir` | No |  | Host cache directory. Empty defaults to `$RUNNER_TEMP/pre-commit-cache`. |
| `run-args` | No | `--all-files --verbose --show-diff-on-failure --color always` | Arguments passed to `pre-commit run`. |

## Outputs

| Output | Description |
| --- | --- |
| `cache-dir` | Resolved host cache directory. |

## Usage

### Basic With Defaults Shown

Use this form when documenting or reviewing the full action contract. The empty cache input is intentional; the action resolves it to `$RUNNER_TEMP/pre-commit-cache`.

```yaml
name: Pre-commit

on:
  pull_request:
  workflow_dispatch:

permissions:
  contents: read

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # actions/checkout@v6.0.2 release: https://github.com/actions/checkout/releases/tag/v6.0.2
        with:
          persist-credentials: false

      - uses: pagopa/<repo-actions>/actions/global/pre-commit@<sha>
        with:
          pre-commit-image: ghcr.io/antonbabenko/pre-commit-terraform:v1.105.0@sha256:4ef4b8323b27fc263535ad88c9d2f20488fcb3b520258e5e7f0553ed5f6692b5
          pre-commit-config: .pre-commit-config.yaml
          pre-commit-cache-dir: ""
          run-args: --all-files --verbose --show-diff-on-failure --color always
```

### With Caller-Owned Cache

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # actions/checkout@v6.0.2 release: https://github.com/actions/checkout/releases/tag/v6.0.2
    with:
      persist-credentials: false

  - uses: actions/cache/restore@27d5ce7f107fe9357f9df03efb73ab90386fccae # actions/cache/restore@v5.0.5 release: https://github.com/actions/cache/releases/tag/v5.0.5
    with:
      path: ${{ runner.temp }}/pre-commit-cache
      key: pre-commit-${{ runner.os }}-${{ hashFiles('.pre-commit-config.yaml') }}

  - uses: pagopa/<repo-actions>/actions/global/pre-commit@<sha>
    with:
      pre-commit-cache-dir: ${{ runner.temp }}/pre-commit-cache
```

## Troubleshooting

### `pre-commit config not found`

- Ensure the checkout step ran before this action.
- Confirm `pre-commit-config` is relative to the workspace root.

### Container image rejected

- `pre-commit-image` must include `@sha256:<digest>`.
- Keep the human-readable tag beside the digest for reviewability.
