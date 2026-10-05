# Tests

Each test directory mirrors the path of the component that owns the behavior.
Find the owner by removing the leading `tests/` from the path.

| Test directory | Owner | Runner |
| --- | --- | --- |
| `tests/actions/global/semantic-release/` | `actions/global/semantic-release/` | Python `unittest` |
| `tests/actions/global/stale-close-pr/` | `actions/global/stale-close-pr/` | Python `unittest` |
| `tests/scripts/aws/terraform-sh/` | `scripts/aws/terraform-sh/` | Python `unittest` |
| `tests/scripts/aws/aws-terraform-s3-state-creator/` | `scripts/aws/aws-terraform-s3-state-creator/` | `run.sh` |
| `tests/scripts/aws/terraform-dynamic-states/` | `scripts/aws/terraform-dynamic-states/` | `run.sh` |
| `tests/scripts/cross-provider/terraform-sh/` | `scripts/{aws,azure,gcp}/terraform-sh/` together | `run.sh` |
| `tests/tools/validate_repo_locally/` | `tools/validate_repo_locally/` | Python `unittest` |

`tests/scripts/cross-provider/` holds suites that check several provider
components at once. Its `fakes/`, `fixtures/`, and `lib/` directories are also
the shared test doubles for the provider-specific suites.

`actions/global/release-please-google/tests/` stays inside its action because
that action owns and runs its own tests.

Run everything with `make test`, or a single area with `make python-tests`,
`make terraform-wrapper-tests`, `make aws-s3-state-creator-tests`, or
`make aws-dynamic-states-tests`. CI runs the same targets in the
`Repository Tests` job of `.github/workflows/_code-analysis.yml`.
