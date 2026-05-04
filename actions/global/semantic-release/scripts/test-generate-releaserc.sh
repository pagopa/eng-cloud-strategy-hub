#!/usr/bin/env bash
#
# Purpose: Validate semantic-release config generation without calling GitHub APIs.
# Usage examples:
#   bash actions/global/semantic-release/scripts/test-generate-releaserc.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${SCRIPT_DIR}/generate-releaserc.py"
TEMP_DIR=""

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

trap cleanup EXIT

log_info() {
  echo "ℹ️  $*"
}

log_success() {
  echo "✅ $*"
}

fail() {
  echo "❌ $*" >&2
  exit 1
}

expect_failure() {
  local test_name="$1"
  local expected_message="$2"
  shift 2
  local stderr_file="${TEMP_DIR}/${test_name// /-}.stderr"

  if "$@" 2>"${stderr_file}"; then
    fail "${test_name} was expected to fail."
  fi

  if ! grep -Fq "${expected_message}" "${stderr_file}"; then
    echo "Expected error containing: ${expected_message}" >&2
    echo "Actual stderr:" >&2
    cat "${stderr_file}" >&2
    fail "${test_name} produced an unexpected error message."
  fi
}

main() {
  local output_file

  TEMP_DIR="$(mktemp -d)"
  output_file="${TEMP_DIR}/.releaserc.json"

  log_info "Running semantic-release config generation success path"
  python3 "${SCRIPT_PATH}" \
    --output "${output_file}" \
    --branches '["main"]' \
    --tag-format 'v${version}' \
    --preset 'angular' \
    --changelog-file 'CHANGELOG.md' \
    --git-author-name 'github-actions[bot]' \
    --git-author-email '41898282+github-actions[bot]@users.noreply.github.com' \
    --release-rules '[{"type": "breaking", "release": "major"}]' \
    --debug 'false'

  grep -Fq '"tagFormat": "v${version}"' "${output_file}" || fail "Generated config is missing tagFormat."
  grep -Fq '"@semantic-release/git"' "${output_file}" || fail "Generated config is missing the git plugin."
  grep -Fq '[skip ci]' "${output_file}" || fail "Generated config is missing the skip ci commit message marker."

  log_info "Running invalid branches JSON validation"
  expect_failure \
    "invalid branches json" \
    "branches must be valid JSON" \
    python3 "${SCRIPT_PATH}" \
      --output "${output_file}" \
      --branches 'not-json' \
      --tag-format 'v${version}' \
      --preset 'angular' \
      --changelog-file 'CHANGELOG.md' \
      --git-author-name 'github-actions[bot]' \
      --git-author-email '41898282+github-actions[bot]@users.noreply.github.com' \
      --release-rules '[{"type": "breaking", "release": "major"}]' \
      --debug 'false'

  log_info "Running invalid release rules validation"
  expect_failure \
    "invalid release rules json" \
    "release_rules must be valid JSON" \
    python3 "${SCRIPT_PATH}" \
      --output "${output_file}" \
      --branches '["main"]' \
      --tag-format 'v${version}' \
      --preset 'angular' \
      --changelog-file 'CHANGELOG.md' \
      --git-author-name 'github-actions[bot]' \
      --git-author-email '41898282+github-actions[bot]@users.noreply.github.com' \
      --release-rules 'not-json' \
      --debug 'false'

  log_success "semantic-release config generation checks passed"
}

main "$@"
