#!/usr/bin/env bash
#
# Purpose: Validate terraform-dynamic-states behavior with fake AWS and Terraform CLIs.
# Usage examples:
#   ./tests/scripts/aws_terraform_dynamic_states/run.sh
#   bash tests/scripts/aws_terraform_dynamic_states/run.sh

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
REPO_ROOT="$(cd -- "${TEST_DIR}/../../.." && pwd)"
readonly REPO_ROOT
SCRIPT_UNDER_TEST="${REPO_ROOT}/scripts/aws/terraform-dynamic-states.sh"
readonly SCRIPT_UNDER_TEST
FIXTURE_ROOT="${TEST_DIR}/fixtures/dynamic-root"
readonly FIXTURE_ROOT
FAKES_DIR="${TEST_DIR}/fakes"
readonly FAKES_DIR
LOG_DIR="${TEST_DIR}/logs"
readonly LOG_DIR
LOCK_LISTING_FILE="${FIXTURE_ROOT}/lock-listing.json"
readonly LOCK_LISTING_FILE
LOCK_METADATA_DIR="${FIXTURE_ROOT}/locks"
readonly LOCK_METADATA_DIR

# shellcheck source=tests/scripts/terraform_wrappers/lib/assertions.sh
source "${REPO_ROOT}/tests/scripts/terraform_wrappers/lib/assertions.sh"

RUN_STATUS=0
RUN_STDOUT=""
RUN_STDERR=""

reset_logs() {
  rm -rf -- "${LOG_DIR}"
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

  (
    cd "${FIXTURE_ROOT}" || exit 1
    unset AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION
    if [[ -n "${stdin_payload}" ]]; then
      printf '%s' "${stdin_payload}" |
        CI=false FAKE_LOG_DIR="${LOG_DIR}" \
          FAKE_S3_LISTING_FILE="${LOCK_LISTING_FILE}" \
          FAKE_LOCK_METADATA_DIR="${LOCK_METADATA_DIR}" \
          PATH="${FAKES_DIR}:$PATH" "${SCRIPT_UNDER_TEST}" "$@"
    else
      CI=false FAKE_LOG_DIR="${LOG_DIR}" \
        FAKE_S3_LISTING_FILE="${LOCK_LISTING_FILE}" \
        FAKE_LOCK_METADATA_DIR="${LOCK_METADATA_DIR}" \
        PATH="${FAKES_DIR}:$PATH" "${SCRIPT_UNDER_TEST}" "$@"
    fi
  ) >"${stdout_file}" 2>"${stderr_file}" || RUN_STATUS=$?

  RUN_STDOUT="$(cat "${stdout_file}")"
  RUN_STDERR="$(cat "${stderr_file}")"
}

test_help_outputs_dynamic_actions() {
  reset_logs
  run_script "" help
  assert_eq "0" "${RUN_STATUS}" "dynamic help exits cleanly"
  assert_contains "${RUN_STDOUT}" "version 1.9" "dynamic help prints the current version"
  assert_contains "${RUN_STDOUT}" "find-locks" "dynamic help documents lock inventory"
  assert_contains "${RUN_STDOUT}" "unlock-all" "dynamic help documents bulk unlock"
  assert_contains "${RUN_STDOUT}" "--state-variable" "dynamic help documents the scope variable override"
  assert_file_not_exists "${LOG_DIR}/terraform.log" "dynamic help must not call Terraform"
  assert_file_not_exists "${LOG_DIR}/aws.log" "dynamic help must not call AWS"
}

test_scope_is_required_for_actions() {
  reset_logs
  run_script "" plan
  assert_eq "1" "${RUN_STATUS}" "dynamic action without scope fails"
  assert_contains "${RUN_STDERR}" "Missing scope argument" "missing scope is reported"
}

test_plan_uses_dynamic_backend_and_scope_variable() {
  reset_logs
  run_script "" plan dev --cicd --tfvars overrides/custom.tfvars
  assert_eq "0" "${RUN_STATUS}" "dynamic plan exits cleanly"
  assert_file_contains "${LOG_DIR}/terraform.log" '-backend-config=bucket=dynamic-state-bucket' "dynamic plan configures the S3 bucket"
  assert_file_contains "${LOG_DIR}/terraform.log" '-backend-config=key=terraform/dev/tfstate' "dynamic plan derives the scoped state key"
  assert_file_contains "${LOG_DIR}/terraform.log" '-var=workload_scope=dev' "dynamic plan passes the configured scope variable"
  assert_file_contains "${LOG_DIR}/terraform.log" 'env/terraform.tfvars' "dynamic plan loads global tfvars"
  assert_file_contains "${LOG_DIR}/terraform.log" 'env/dev-terraform.tfvars' "dynamic plan loads scope tfvars"
  assert_file_contains "${LOG_DIR}/terraform.log" 'overrides/custom.tfvars' "dynamic plan keeps explicit tfvars overrides"
  assert_file_contains "${LOG_DIR}/terraform.log" 'env=AWS_PROFILE=fake-profile AWS_REGION=eu-south-1' "dynamic plan exports the configured AWS context"
  assert_file_not_exists "${LOG_DIR}/aws.log" "CI dynamic plan skips interactive AWS profile checks"
}

test_dry_run_prints_commands_without_execution() {
  reset_logs
  run_script "" plan dev --cicd --dry-run --state-variable tenant_scope
  assert_eq "0" "${RUN_STATUS}" "dynamic dry-run exits cleanly"
  assert_contains "${RUN_STDOUT}" '$ terraform init -reconfigure' "dynamic dry-run prints initialization"
  assert_contains "${RUN_STDOUT}" '-backend-config=key=terraform/dev/tfstate' "dynamic dry-run prints the scoped backend key"
  assert_contains "${RUN_STDOUT}" '-var=tenant_scope=dev' "dynamic dry-run prints the overridden scope variable"
  assert_file_not_exists "${LOG_DIR}/terraform.log" "dynamic dry-run does not execute Terraform"
}

test_invalid_state_variable_is_rejected() {
  reset_logs
  run_script "" plan dev --cicd --state-variable 'invalid-name'
  assert_eq "1" "${RUN_STATUS}" "invalid state variable exits with failure"
  assert_contains "${RUN_STDERR}" "Invalid --state-variable 'invalid-name'" "invalid state variable is reported"
}

test_find_locks_reads_scope_metadata() {
  reset_logs
  run_script "" find-locks dev --cicd --debug
  assert_eq "0" "${RUN_STATUS}" "dynamic lock inventory exits cleanly"
  assert_contains "${RUN_STDOUT}" "LOCK INVENTORY" "lock inventory prints its heading"
  assert_contains "${RUN_STDOUT}" "scope      dev" "lock inventory prints the requested scope"
  assert_contains "${RUN_STDOUT}" "lock id    lock-dev-123" "lock inventory prints lock metadata"
  assert_contains "${RUN_STDOUT}" "operation  OperationTypeApply" "lock inventory prints the lock operation"
  assert_file_contains "${LOG_DIR}/aws.log" 's3api list-objects-v2' "lock inventory lists S3 objects"
  assert_file_contains "${LOG_DIR}/aws.log" 's3 cp s3://dynamic-state-bucket/terraform/dev/tfstate.tflock' "lock inventory reads the matching lock document"
  assert_contains "${RUN_STDERR}" 'event=inventory stage=list result=success scope=dev' "debug output records successful inventory"
  assert_file_not_exists "${LOG_DIR}/terraform.log" "lock inventory does not call Terraform"
}

test_bulk_unlock_dry_run_is_read_only() {
  reset_logs
  run_script "" unlock-all all --cicd --dry-run
  assert_eq "0" "${RUN_STATUS}" "bulk unlock dry-run exits cleanly"
  assert_contains "${RUN_STDOUT}" 'terraform force-unlock -force lock-dev-123' "bulk unlock dry-run prints the dev unlock"
  assert_contains "${RUN_STDOUT}" 'terraform force-unlock -force lock-prod-456' "bulk unlock dry-run prints the prod unlock"
  assert_file_not_exists "${LOG_DIR}/terraform.log" "bulk unlock dry-run does not execute Terraform"
}

test_doctor_checks_dynamic_context() {
  reset_logs
  run_script "" doctor dev --cicd
  assert_eq "0" "${RUN_STATUS}" "dynamic doctor exits cleanly"
  assert_contains "${RUN_STDOUT}" 'backend config found' "dynamic doctor finds the backend config"
  assert_contains "${RUN_STDOUT}" 'AWS credentials valid for profile fake-profile' "dynamic doctor checks the configured AWS profile"
  assert_contains "${RUN_STDOUT}" 'Global tfvars found' "dynamic doctor finds global tfvars"
  assert_contains "${RUN_STDOUT}" 'Scope tfvars found' "dynamic doctor finds scope tfvars"
}

cleanup_runtime_artifacts() {
  rm -rf -- "${LOG_DIR}"
  rm -rf -- "${FIXTURE_ROOT}/.terraform"
  rm -f -- "${FIXTURE_ROOT}/tfplan" "${FIXTURE_ROOT}"/tfplan.*
}

run_test() {
  local test_name="$1"

  printf 'ℹ️  Running %s\n' "${test_name}"
  "${test_name}"
  printf '✅ Passed %s\n' "${test_name}"
}

main() {
  local tests=(
    test_help_outputs_dynamic_actions
    test_scope_is_required_for_actions
    test_plan_uses_dynamic_backend_and_scope_variable
    test_dry_run_prints_commands_without_execution
    test_invalid_state_variable_is_rejected
    test_find_locks_reads_scope_metadata
    test_bulk_unlock_dry_run_is_read_only
    test_doctor_checks_dynamic_context
  )
  local test_name=""

  for test_name in "${tests[@]}"; do
    run_test "${test_name}"
  done

  success "terraform-dynamic-states test suite completed"
  cleanup_runtime_artifacts
}

main "$@"
