# Pre-commit Container Runner

Runs repository `pre-commit` checks inside the pinned `pre-commit-terraform` container image.

## Behavior

- Validates that the container image is pinned by digest.
- Uses `PRE_COMMIT_HOME` mounted from a caller-provided cache directory.
- Sets `TF_INPUT=0` and `TF_IN_AUTOMATION=1` for Terraform hooks.
- Leaves `actions/cache` restore/save orchestration in the caller workflow.

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

```yaml
steps:
  - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # actions/checkout@v6.0.2 release: https://github.com/actions/checkout/releases/tag/v6.0.2
    with:
      persist-credentials: false

  - uses: ./actions/global/pre-commit
    with:
      pre-commit-cache-dir: ${{ runner.temp }}/pre-commit-cache
```
