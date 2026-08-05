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

test_invalid_bucket_shape_is_rejected() {
  reset_logs
  run_script "" --region eu-south-1 --account-name sandbox --bucket 192.168.0.1
  assert_eq "1" "${RUN_STATUS}" "ip-like bucket exits with failure"
  assert_contains "${RUN_STDERR}" "Bucket name is not a valid S3 bucket name" "invalid bucket shape is reported"
}

test_invalid_tag_format_is_rejected() {
  reset_logs
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --tag InvalidTag
  assert_eq "1" "${RUN_STATUS}" "invalid tag format exits with failure"
  assert_contains "${RUN_STDERR}" "Invalid --tag format" "invalid tag format is reported"
}

test_account_name_mismatch_fails() {
  reset_logs
  export FAKE_ACCOUNT_NAME="prod"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_NAME
  assert_eq "1" "${RUN_STATUS}" "account name mismatch exits with failure"
  assert_contains "${RUN_STDERR}" "Account name mismatch" "account name mismatch is reported"
}

test_dry_run_create_mode() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="notfound"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "dry-run create mode exits cleanly"
  assert_contains "${RUN_STDOUT}" "Operation     : 🆕 CREATE - new bucket will be created before applying baseline controls" "plan reports create operation"
  assert_contains "${RUN_STDOUT}" "🧭 Terraform State Bucket Plan" "plan has a clear visual heading"
  assert_contains "${RUN_STDOUT}" "      Benefit : Provides a recovery path for state changes" "plan explains the recovery baseline"
  assert_contains "${RUN_STDOUT}" "      Details : Not managed by recovery baseline" "plan makes Object Lock scope explicit"
  assert_not_contains "${RUN_STDOUT}" "Mode          :" "plan omits duplicate mode row"
  assert_not_contains "${RUN_STDOUT}" "Bucket State  :" "plan omits duplicate bucket state row"
  assert_contains "${RUN_STDOUT}" "[🆕 CREATE] 🪣 BUCKET — DRY-RUN: s3api create-bucket" "dry-run create action is labeled"
  assert_not_contains "${RUN_STDOUT}" "--object-lock-enabled-for-bucket" "dry-run does not plan irreversible Object Lock"
  assert_contains "${RUN_STDOUT}" "Dry run completed" "dry-run completion is reported"
  assert_aws_log_contains "sts get-caller-identity" "identity check was executed"
  assert_aws_log_contains "organizations describe-account" "account name lookup was executed"
  assert_aws_log_contains "s3api head-bucket" "bucket mode detection was executed"
  assert_aws_log_not_contains "s3api put-bucket-tagging" "dry-run skips mutating calls"
}

test_dry_run_explains_control_benefits() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="notfound"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "dry-run benefit report exits cleanly"
  assert_contains "${RUN_STDOUT}" $'  - 🪣 Bucket creation\n      Details : Dedicated S3 bucket for Terraform state\n      Benefit : Isolates state data from other workloads' "bucket creation uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 🧾 Versioning\n      Details : Enabled and verified after apply\n      Benefit : Recovers earlier state versions after accidental overwrites or deletions' "versioning uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 🚫 Public access\n      Details : Blocked at bucket level (ACL + bucket policy public exposure prevented)\n      Benefit : Prevents accidental public exposure of Terraform state' "public access uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 👤 Object Ownership\n      Details : BucketOwnerEnforced\n      Benefit : Keeps object ownership with the bucket account and removes ACL-based ambiguity' "ownership uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 🔐 Default encryption\n      Details : SSE-S3 (AES256)\n      Benefit : Protects state data at rest by default' "encryption uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 🌐 TLS-only bucket policy\n      Details : Existing statements preserved; non-HTTPS requests denied\n      Benefit : Blocks state transfers over unencrypted connections' "transport uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - ♻️ Recovery baseline\n      Details : S3 versioning will be enabled on apply\n      Benefit : Provides a recovery path for state changes' "recovery baseline uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 🧱 Object Lock\n      Details : Not managed by recovery baseline\n      Benefit : Keeps retention policy reversible and explicit' "object lock uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - ⏳ Lifecycle retention\n      Details : Existing rules are not modified by this script\n      Benefit : Preserves current retention behavior and avoids unintended deletion' "lifecycle uses the readable layout"
  assert_contains "${RUN_STDOUT}" $'  - 🏷️ Tags\n      Details : Merged (existing + defaults + optional --tag values)\n      Benefit : Improves ownership, searchability, and governance' "tagging uses the readable layout"
  assert_not_contains "${RUN_STDOUT}" " — Benefit:" "benefits are not concatenated with feature details"
}

test_dry_run_reports_preflight_progress() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="notfound"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "preflight progress dry-run exits cleanly"
  assert_contains "${RUN_STDOUT}" "🚀 [START] Preparing Terraform state bucket operation" "startup progress is reported"
  assert_contains "${RUN_STDOUT}" "🔐 [IDENTITY] Verifying AWS caller and expected account" "identity progress is reported"
  assert_contains "${RUN_STDOUT}" "✅ [IDENTITY] AWS account verified: sandbox" "identity completion is reported"
  assert_contains "${RUN_STDOUT}" "🪣 [BUCKET] Inspecting bucket my-tf-state accessibility and current state" "bucket inspection progress is reported"
  assert_contains "${RUN_STDOUT}" "✅ [BUCKET] Mode detected: 🆕 CREATE" "bucket mode completion is reported"
}

test_create_mode_uses_recovery_baseline_without_object_lock() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="notfound"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "create mode recovery baseline exits cleanly"
  assert_aws_log_contains "s3api create-bucket" "create mode creates the bucket"
  assert_aws_log_not_contains "--object-lock-enabled-for-bucket" "create mode does not enable irreversible Object Lock"
  assert_contains "${RUN_STDOUT}" "🪣 BUCKET — Creating bucket my-tf-state" "create log identifies the bucket phase"
  assert_contains "${RUN_STDOUT}" "✅ [VERIFY] S3 versioning is enabled" "create mode reports verified versioning"
}

test_dry_run_forbidden_bucket_is_read_only_and_non_interactive() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="forbidden"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "dry-run with an inaccessible bucket exits cleanly"
  assert_contains "${RUN_STDOUT}" "Execution mode : 🧪 DRY-RUN (read-only)" "dry-run mode is explicit in the plan"
  assert_contains "${RUN_STDOUT}" "access could not be verified" "dry-run explains the inaccessible bucket"
  assert_contains "${RUN_STDOUT}" "Dry run completed" "dry-run completion is reported"
  assert_not_contains "${RUN_STDOUT}" "Proceed with" "dry-run does not ask for confirmation"
  assert_aws_log_not_contains "s3api create-bucket" "dry-run does not create an inaccessible bucket"
  assert_aws_log_not_contains "s3api put-bucket" "dry-run skips bucket mutations"
}

test_update_mode_applies_controls() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "update mode exits cleanly"
  assert_contains "${RUN_STDOUT}" "Operation     : ♻️ UPDATE - existing bucket will be updated in place with baseline controls" "plan reports update operation"
  assert_not_contains "${RUN_STDOUT}" "Mode          :" "plan omits duplicate mode row"
  assert_not_contains "${RUN_STDOUT}" "Bucket State  :" "plan omits duplicate bucket state row"
  assert_contains "${RUN_STDOUT}" "[♻️ UPDATE] 🏷️ TAGS — Applying merged bucket tags" "update tagging step is labeled"
  assert_aws_log_contains "s3api put-bucket-versioning" "versioning call is executed"
  assert_aws_log_contains "s3api put-public-access-block" "public access block call is executed"
  assert_aws_log_contains "s3api put-bucket-ownership-controls" "ownership controls call is executed"
  assert_aws_log_contains "s3api put-bucket-encryption" "encryption call is executed"
  assert_aws_log_contains "s3api put-bucket-policy" "tls-only policy call is executed"
  assert_aws_log_contains "s3api put-bucket-tagging" "tagging call is executed"
  assert_aws_log_contains "s3api get-bucket-versioning" "versioning state is verified after the write"
  assert_contains "${RUN_STDOUT}" "🧾 VERSIONING" "versioning log identifies its phase"
  assert_contains "${RUN_STDOUT}" "🔐 ENCRYPTION" "encryption log identifies its phase"
  assert_contains "${RUN_STDOUT}" "✅ [VERIFY] S3 versioning is enabled" "verified versioning is reported clearly"
}

test_versioning_verification_fails_when_not_enabled() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  export FAKE_VERSIONING_STATUS="Suspended"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  unset FAKE_VERSIONING_STATUS
  assert_eq "1" "${RUN_STATUS}" "non-enabled versioning fails the configuration"
  assert_contains "${RUN_STDERR}" "S3 versioning verification failed" "versioning verification failure is actionable"
}

test_update_mode_uses_expected_bucket_owner() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "update mode exits cleanly with expected owner guards"
  assert_aws_log_contains "--expected-bucket-owner 123456789012" "bucket owner guard is passed to S3 calls"
}

test_update_mode_merges_existing_bucket_policy() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  export FAKE_BUCKET_POLICY_MODE="exists"
  export FAKE_ASSERT_POLICY_MERGE="true"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  unset FAKE_BUCKET_POLICY_MODE
  unset FAKE_ASSERT_POLICY_MERGE
  assert_eq "0" "${RUN_STATUS}" "update mode preserves existing bucket policy statements"
  assert_aws_log_contains "s3api get-bucket-policy" "existing bucket policy is read before writing"
}

test_update_mode_merges_existing_tags_with_user_precedence() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  export FAKE_BUCKET_TAGGING_MODE="exists"
  export FAKE_ASSERT_TAG_MERGE="true"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --tag Environment=dev --yes
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  unset FAKE_BUCKET_TAGGING_MODE
  unset FAKE_ASSERT_TAG_MERGE
  assert_eq "0" "${RUN_STATUS}" "update mode preserves existing tags and lets user tags win"
  assert_aws_log_contains "s3api get-bucket-tagging" "existing bucket tags are read before writing"
}

test_account_service_fallback_when_org_denied() {
  reset_logs
  export FAKE_ORG_MODE="denied"
  export FAKE_ACCOUNT_SERVICE_MODE="ok"
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  run_script "" --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run --yes
  unset FAKE_ORG_MODE
  unset FAKE_ACCOUNT_SERVICE_MODE
  unset FAKE_ACCOUNT_NAME
  unset FAKE_HEAD_BUCKET_MODE
  assert_eq "0" "${RUN_STATUS}" "fallback to account service exits cleanly"
  assert_aws_log_contains "organizations describe-account" "organizations lookup is attempted first"
  assert_aws_log_contains "account get-account-information" "account service fallback is executed"
}

test_operator_can_cancel() {
  reset_logs
  export FAKE_ACCOUNT_NAME="sandbox"
  export FAKE_HEAD_BUCKET_MODE="exists"
  run_script $'n\n' --region eu-south-1 --account-name sandbox --bucket my-tf-state
  unset FAKE_ACCOUNT_NAME
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
    test_invalid_bucket_shape_is_rejected
    test_invalid_tag_format_is_rejected
    test_account_name_mismatch_fails
    test_dry_run_create_mode
    test_dry_run_explains_control_benefits
    test_dry_run_reports_preflight_progress
    test_create_mode_uses_recovery_baseline_without_object_lock
    test_dry_run_forbidden_bucket_is_read_only_and_non_interactive
    test_update_mode_applies_controls
    test_versioning_verification_fails_when_not_enabled
    test_update_mode_uses_expected_bucket_owner
    test_update_mode_merges_existing_bucket_policy
    test_update_mode_merges_existing_tags_with_user_precedence
    test_account_service_fallback_when_org_denied
    test_operator_can_cancel
  )
  local test_name=""

  for test_name in "${tests[@]}"; do
    run_test "${test_name}"
  done

  success "aws-terraform-s3-state-creator test suite completed"
}

main "$@"
