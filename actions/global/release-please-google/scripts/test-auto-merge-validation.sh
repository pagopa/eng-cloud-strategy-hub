#!/usr/bin/env bash
#
# Purpose: Validate release-please auto-merge script input handling without GitHub API calls.
# Usage examples:
#   bash actions/global/release-please-google/scripts/test-auto-merge-validation.sh

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_PATH="${SCRIPT_DIR}/auto-merge-release-pr.sh"
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
  local stdout_file="$3"
  local stderr_file="$4"
  shift 4

  if "$@" >"${stdout_file}" 2>"${stderr_file}"; then
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
  local stdout_file
  local stderr_file

  TEMP_DIR="$(mktemp -d)"
  output_file="${TEMP_DIR}/outputs.txt"
  stdout_file="${TEMP_DIR}/stdout.txt"
  stderr_file="${TEMP_DIR}/stderr.txt"

  log_info "Running success-path validation without GitHub API calls"
  GITHUB_TOKEN="fake-token" \
  GITHUB_OUTPUT="${output_file}" \
  GITHUB_REPOSITORY="pagopa/eng-cloud-strategy-hub" \
  GITHUB_SERVER_URL="https://github.com" \
  RP_TARGET_BRANCH="main" \
  RP_AUTO_MERGE="false" \
  RP_MERGE_METHOD="squash" \
  RP_PR='{"number":42,"headBranchName":"release-please--branches--main","baseBranchName":"main","title":"chore: release main"}' \
  RP_PRS="" \
  RP_DEBUG="false" \
  bash "${SCRIPT_PATH}" >"${stdout_file}" 2>"${stderr_file}"

  grep -Fq "pr=https://github.com/pagopa/eng-cloud-strategy-hub/pull/42" "${output_file}" || fail "Success path did not emit the release PR URL."
  grep -Fq "auto_merge_enabled=false" "${output_file}" || fail "Success path did not emit auto_merge_enabled=false."

  log_info "Running invalid merge method validation"
  expect_failure \
    "invalid merge method" \
    "RP_MERGE_METHOD must be one of: merge, squash, rebase." \
    "${stdout_file}" \
    "${stderr_file}" \
    env \
      GITHUB_TOKEN="fake-token" \
      GITHUB_OUTPUT="${output_file}" \
      GITHUB_REPOSITORY="pagopa/eng-cloud-strategy-hub" \
      GITHUB_SERVER_URL="https://github.com" \
      RP_TARGET_BRANCH="main" \
      RP_AUTO_MERGE="false" \
      RP_MERGE_METHOD="invalid" \
      RP_PR="" \
      RP_PRS="" \
      RP_DEBUG="false" \
      bash "${SCRIPT_PATH}"

  log_info "Running invalid boolean validation"
  expect_failure \
    "invalid boolean" \
    "RP_AUTO_MERGE must be 'true' or 'false'." \
    "${stdout_file}" \
    "${stderr_file}" \
    env \
      GITHUB_TOKEN="fake-token" \
      GITHUB_OUTPUT="${output_file}" \
      GITHUB_REPOSITORY="pagopa/eng-cloud-strategy-hub" \
      GITHUB_SERVER_URL="https://github.com" \
      RP_TARGET_BRANCH="main" \
      RP_AUTO_MERGE="maybe" \
      RP_MERGE_METHOD="squash" \
      RP_PR="" \
      RP_PRS="" \
      RP_DEBUG="false" \
      bash "${SCRIPT_PATH}"

  log_info "Running missing token validation"
  expect_failure \
    "missing token" \
    "GITHUB_TOKEN is required." \
    "${stdout_file}" \
    "${stderr_file}" \
    env \
      GITHUB_TOKEN="" \
      GITHUB_OUTPUT="${output_file}" \
      GITHUB_REPOSITORY="pagopa/eng-cloud-strategy-hub" \
      GITHUB_SERVER_URL="https://github.com" \
      RP_TARGET_BRANCH="main" \
      RP_AUTO_MERGE="false" \
      RP_MERGE_METHOD="squash" \
      RP_PR="" \
      RP_PRS="" \
      RP_DEBUG="false" \
      bash "${SCRIPT_PATH}"

  log_success "release-please auto-merge validation checks passed"
}

main "$@"
