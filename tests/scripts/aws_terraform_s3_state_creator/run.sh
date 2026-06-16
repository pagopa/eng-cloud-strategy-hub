#!/usr/bin/env bash
#
# Purpose: Validate aws-terraform-s3-state-creator behavior with a fake AWS CLI.
# Usage examples:
#   ./tests/scripts/aws_terraform_s3_state_creator/run.sh
#   bash tests/scripts/aws_terraform_s3_state_creator/run.sh

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
REPO_ROOT="$(cd -- "${TEST_DIR}/../../.." && pwd)"
readonly REPO_ROOT
SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/aws/aws-terraform-s3-state-creator.sh"
readonly SCRIPT_UNDER_TEST
FAKES_DIR="${TEST_DIR}/fakes"
readonly FAKES_DIR
LOG_DIR="${TEST_DIR}/logs"
readonly LOG_DIR

# shellcheck source=tests/scripts/terraform_wrappers/lib/assertions.sh
source "${REPO_ROOT}/tests/scripts/terraform_wrappers/lib/assertions.sh"

RUN_STATUS=0
RUN_STDOUT=""
RUN_STDERR=""

reset_logs() {
  rm -rf "${LOG_DIR}"
  mkdir -p "${LOG_DIR}"
}

run_script() {
  local stdin_payload="$1"
  shift

  local stdout_file="${LOG_DIR}/stdout.log"
  local stderr_file="${LOG_DIR}/stderr.log"

  RUN_STATUS=0
  RUN_STDOUT=""
  RUN_STDERR=""

  if [[ -n "${stdin_payload}" ]]; then
    printf '%s' "${stdin_payload}" |
      PATH="${FAKES_DIR}:$PATH" FAKE_AWS_LOG="${LOG_DIR}/aws.log" bash "${SCRIPT_UNDER_TEST}" "$@" >"${stdout_file}" 2>"${stderr_file}" || RUN_STATUS=$?
  else
    PATH="${FAKES_DIR}:$PATH" FAKE_AWS_LOG="${LOG_DIR}/aws.log" bash "${SCRIPT_UNDER_TEST}" "$@" >"${stdout_file}" 2>"${stderr_file}" || RUN_STATUS=$?
  fi

  RUN_STDOUT="$(cat "${stdout_file}")"
  RUN_STDERR="$(cat "${stderr_file}")"
}

assert_aws_log_contains() {
  local needle="$1"
  local message="$2"

  assert_file_contains "${LOG_DIR}/aws.log" "${needle}" "${message}"
}

assert_aws_log_not_contains() {
  local needle="$1"
  local message="$2"
  local content=""

  [[ -f "${LOG_DIR}/aws.log" ]] || fail "${message}: aws log not found"
  content="$(cat "${LOG_DIR}/aws.log")"
  assert_not_contains "${content}" "${needle}" "${message}"
}

test_help_without_args() {
  reset_logs
  run_script ""
  assert_eq "0" "${RUN_STATUS}" "no-args help exits cleanly"
  assert_contains "${RUN_STDOUT}" "Create or align a secure S3 bucket" "help text is shown"
}

test_missing_required_args() {
  reset_logs
  run_script "" --region eu-south-1
  assert_eq "1" "${RUN_STATUS}" "missing required args exits with failure"
  assert_contains "${RUN_STDERR}" "--account-name is required" "missing account-name is reported"
}

test_uppercase_bucket_is_rejected() {
  reset_logs
  run_script "" --region eu-south-1 --account-name sandbox --bucket MyStateBucket
  assert_eq "1" "${RUN_STATUS}" "uppercase bucket exits with failure"
  assert_contains "${RUN_STDERR}" "Bucket name must be lowercase" "uppercase validation error is shown"
}

test_invalid_tag_format_is_rejected() {
  reset_logs
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --tag InvalidTag
  assert_eq "1" "${RUN_STATUS}" "invalid tag format exits with failure"
  assert_contains "${RUN_STDERR}" "Invalid --tag format" "invalid tag format is reported"
}

test_account_alias_mismatch_fails() {
  reset_logs
  export FAKE_ACCOUNT_ALIAS="prod"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_ALIAS
  assert_eq "1" "${RUN_STATUS}" "account alias mismatch exits with failure"
  assert_contains "${RUN_STDERR}" "Account alias mismatch" "alias mismatch is reported"
}

test_dry_run_create_mode() {
  reset_logs
  export FAKE_ACCOUNT_ALIAS="sandbox"
  export FAKE_HEAD_BUCKET_MODE="notfound"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run --yes
  unset FAKE_ACCOUNT_ALIAS
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "dry-run create mode exits cleanly"
  assert_contains "${RUN_STDOUT}" "Mode          : create" "plan reports create mode"
  assert_contains "${RUN_STDOUT}" "DRY-RUN: s3api create-bucket" "dry-run includes create-bucket action"
  assert_contains "${RUN_STDOUT}" "Dry run completed" "dry-run completion is reported"
  assert_aws_log_contains "sts get-caller-identity" "identity check was executed"
  assert_aws_log_contains "iam list-account-aliases" "account alias check was executed"
  assert_aws_log_contains "s3api head-bucket" "bucket mode detection was executed"
  assert_aws_log_not_contains "s3api put-bucket-tagging" "dry-run skips mutating calls"
}

test_update_mode_applies_controls() {
  reset_logs
  export FAKE_ACCOUNT_ALIAS="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_ALIAS
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "update mode exits cleanly"
  assert_contains "${RUN_STDOUT}" "Mode          : update" "plan reports update mode"
  assert_aws_log_contains "s3api put-bucket-versioning" "versioning call is executed"
  assert_aws_log_contains "s3api put-public-access-block" "public access block call is executed"
  assert_aws_log_contains "s3api put-bucket-ownership-controls" "ownership controls call is executed"
  assert_aws_log_contains "s3api put-bucket-encryption" "encryption call is executed"
  assert_aws_log_contains "s3api put-bucket-policy" "tls-only policy call is executed"
  assert_aws_log_contains "s3api put-bucket-tagging" "tagging call is executed"
}

test_operator_can_cancel() {
  reset_logs
  export FAKE_ACCOUNT_ALIAS="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  run_script $'n\n' --region eu-south-1 --account-name sandbox --bucket my-tf-state
  unset FAKE_ACCOUNT_ALIAS
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "operator cancellation exits cleanly"
  assert_contains "${RUN_STDOUT}" "Operation cancelled" "cancellation is reported"
  assert_not_contains "${RUN_STDOUT}" "Bucket my-tf-state is configured" "script does not report successful mutation"
}

run_test() {
  local test_name="$1"

  printf 'ℹ️  Running %s\n' "${test_name}"
  "${test_name}"
  printf '✅ Passed %s\n' "${test_name}"
}

main() {
  local tests=(
    test_help_without_args
    test_missing_required_args
    test_uppercase_bucket_is_rejected
    test_invalid_tag_format_is_rejected
    test_account_alias_mismatch_fails
    test_dry_run_create_mode
    test_update_mode_applies_controls
    test_operator_can_cancel
  )
  local test_name=""

  for test_name in "${tests[@]}"; do
    run_test "${test_name}"
  done

  success "aws-terraform-s3-state-creator test suite completed"
}

main "$@"
