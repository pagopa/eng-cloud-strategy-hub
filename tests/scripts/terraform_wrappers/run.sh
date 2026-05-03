#!/usr/bin/env bash
#
# Purpose: Run the Terraform wrapper simulation suite with fake cloud CLIs.
# Usage examples:
#   ./tests/scripts/terraform_wrappers/run.sh
#   bash tests/scripts/terraform_wrappers/run.sh

set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly TEST_DIR
REPO_ROOT="$(cd -- "${TEST_DIR}/../../.." && pwd)"
readonly REPO_ROOT
FIXTURES_DIR="${TEST_DIR}/fixtures"
readonly FIXTURES_DIR
FAKES_DIR="${TEST_DIR}/fakes"
readonly FAKES_DIR

# shellcheck source=tests/scripts/terraform_wrappers/lib/assertions.sh
source "${TEST_DIR}/lib/assertions.sh"

LOG_DIR="${TEST_DIR}/logs"
RUN_STATUS=0
RUN_STDOUT=""
RUN_STDERR=""

reset_logs() {
  rm -rf "${LOG_DIR}"
  mkdir -p "${LOG_DIR}"
}

last_log_line() {
  local tool_name="$1"
  local log_file="${LOG_DIR}/${tool_name}.log"

  [[ -f "$log_file" ]] || return 0
  tail -n 1 "$log_file"
}

assert_no_log() {
  local tool_name="$1"
  local message="$2"
  local log_file="${LOG_DIR}/${tool_name}.log"

  if [[ -f "$log_file" && -s "$log_file" ]]; then
    fail "${message}: unexpected log for ${tool_name}"
  fi
}

cleanup_runtime_artifacts() {
  local provider=""

  rm -rf "${LOG_DIR}"
  for provider in aws azure gcp; do
    rm -rf "${FIXTURES_DIR}/${provider}-root/tmp"
  done
}

build_fake_path_without_summary() {
  local bin_dir="${LOG_DIR}/bin-no-summary"
  local tool_name=""
  local utility_name=""

  mkdir -p "$bin_dir"
  for tool_name in terraform aws az gcloud tflist; do
    ln -sf "${FAKES_DIR}/${tool_name}" "${bin_dir}/${tool_name}"
  done
  for utility_name in awk basename bash cat date grep head mkdir mktemp rm sed; do
    ln -sf "$(command -v "$utility_name")" "${bin_dir}/${utility_name}"
  done
  printf '%s\n' "$bin_dir"
}

run_wrapper_internal() {
  local fake_path="$1"
  local provider="$2"
  local fixture="$3"
  shift 3

  local stdout_file="${LOG_DIR}/${provider}.stdout"
  local stderr_file="${LOG_DIR}/${provider}.stderr"

  RUN_STATUS=0
  RUN_STDOUT=""
  RUN_STDERR=""

  (
    cd "${FIXTURES_DIR}/${fixture}" || exit 1
    CI=false CICD_ENABLE=false FAKE_LOG_DIR="${LOG_DIR}" PATH="${fake_path}:$PATH" bash "${REPO_ROOT}/scripts/${provider}/terraform.sh" "$@"
  ) >"$stdout_file" 2>"$stderr_file" || RUN_STATUS=$?

  RUN_STDOUT="$(cat "$stdout_file")"
  RUN_STDERR="$(cat "$stderr_file")"
}

run_wrapper() {
  local provider="$1"
  local fixture="$2"
  shift 2
  run_wrapper_internal "${FAKES_DIR}" "$provider" "$fixture" "$@"
}

run_wrapper_without_summary() {
  local provider="$1"
  local fixture="$2"
  local fake_path=""
  local stdout_file="${LOG_DIR}/${provider}.stdout"
  local stderr_file="${LOG_DIR}/${provider}.stderr"
  shift 2

  fake_path="$(build_fake_path_without_summary)"
  RUN_STATUS=0
  RUN_STDOUT=""
  RUN_STDERR=""

  (
    cd "${FIXTURES_DIR}/${fixture}" || exit 1
    CI=false CICD_ENABLE=false FAKE_LOG_DIR="${LOG_DIR}" PATH="${fake_path}" bash "${REPO_ROOT}/scripts/${provider}/terraform.sh" "$@"
  ) >"$stdout_file" 2>"$stderr_file" || RUN_STATUS=$?

  RUN_STDOUT="$(cat "$stdout_file")"
  RUN_STDERR="$(cat "$stderr_file")"
}

test_script_metadata() {
  local provider=""

  for provider in aws azure gcp; do
    assert_file_contains "${REPO_ROOT}/scripts/${provider}/terraform.sh" 'vers="1.13"' "${provider} exposes the aligned version"
    assert_file_contains "${REPO_ROOT}/scripts/${provider}/terraform.sh" '# - 1.13 2026-05-03' "${provider} includes the changelog entry"
  done
}

test_help_outputs() {
  local provider=""
  local fixture=""

  for provider in aws azure gcp; do
    reset_logs
    fixture="${provider}-root"
    run_wrapper "$provider" "$fixture" help
    assert_eq "0" "$RUN_STATUS" "${provider} help exits cleanly"
    assert_contains "$RUN_STDOUT" 'version 1.13' "${provider} help prints the version"
    assert_no_log terraform "${provider} help must not call terraform"
    case "$provider" in
      aws)
        assert_no_log aws "aws help must not call aws CLI"
        ;;
      azure)
        assert_no_log az "azure help must not call az CLI"
        ;;
      gcp)
        assert_no_log gcloud "gcp help must not call gcloud CLI"
        ;;
    esac
  done
}

test_clean_removes_local_artifacts() {
  local provider=""
  local fixture_dir=""

  for provider in aws azure gcp; do
    reset_logs
    fixture_dir="${FIXTURES_DIR}/${provider}-root"
    mkdir -p "${fixture_dir}/.terraform"
    : > "${fixture_dir}/tfplan"
    run_wrapper "$provider" "${provider}-root" clean
    assert_eq "0" "$RUN_STATUS" "${provider} clean exits cleanly"
    assert_file_not_exists "${fixture_dir}/.terraform" "${provider} clean removes .terraform"
    assert_file_not_exists "${fixture_dir}/tfplan" "${provider} clean removes tfplan"
  done
}

test_noenv_dry_run_plan() {
  local provider=""

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" plan noenv --no-default-tfvars --dry-run
    assert_eq "0" "$RUN_STATUS" "${provider} noenv dry-run exits cleanly"
    assert_contains "$RUN_STDOUT" 'terraform init -reconfigure' "${provider} noenv dry-run prints init"
    assert_contains "$RUN_STDOUT" 'terraform plan -compact-warnings' "${provider} noenv dry-run prints plan"
    assert_not_contains "$RUN_STDOUT" '-var-file=' "${provider} noenv dry-run omits default tfvars"
    case "$provider" in
      aws)
        assert_no_log aws "${provider} noenv dry-run skips aws CLI"
        ;;
      azure)
        assert_no_log az "${provider} noenv dry-run skips az CLI"
        ;;
      gcp)
        assert_no_log gcloud "${provider} noenv dry-run skips gcloud CLI"
        ;;
    esac
  done
}

test_plan_with_env() {
  reset_logs
  run_wrapper aws aws-root plan dev
  assert_eq "0" "$RUN_STATUS" "aws env plan exits cleanly"
  assert_file_contains "${LOG_DIR}/terraform.log" '-backend-config=bucket=aws-dev-state' 'aws init uses backend config from backend.ini'
  assert_file_contains "${LOG_DIR}/terraform.log" '-var-file=./env/dev/terraform.tfvars' 'aws env plan uses terraform.tfvars'
  assert_file_contains "${LOG_DIR}/aws.log" 'configure list-profiles' 'aws env plan checks configured profiles'

  reset_logs
  run_wrapper azure azure-root plan dev
  assert_eq "0" "$RUN_STATUS" "azure env plan exits cleanly"
  assert_file_contains "${LOG_DIR}/terraform.log" '-backend-config=./env/dev/backend.tfvars' 'azure init uses backend.tfvars'
  assert_file_contains "${LOG_DIR}/terraform.log" '-var-file=./env/dev/terraform.tfvars' 'azure env plan uses terraform.tfvars'
  assert_file_contains "${LOG_DIR}/az.log" 'account set -s 00000000-0000-0000-0000-000000000001' 'azure env plan selects the configured subscription'

  reset_logs
  run_wrapper gcp gcp-root plan dev
  assert_eq "0" "$RUN_STATUS" "gcp env plan exits cleanly"
  assert_file_contains "${LOG_DIR}/terraform.log" '-backend-config=./projects/dev/backend.tfvars' 'gcp init uses backend.tfvars'
  assert_file_contains "${LOG_DIR}/terraform.log" '-var-file=./projects/dev/terraform.tfvars' 'gcp env plan uses terraform.tfvars'
  assert_file_contains "${LOG_DIR}/gcloud.log" 'config set project organization-443016' 'gcp env plan selects the state project'
}

test_json_fallback() {
  local provider=""

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" plan jsononly
    assert_eq "0" "$RUN_STATUS" "${provider} json fallback plan exits cleanly"
    assert_file_contains "${LOG_DIR}/terraform.log" 'terraform.tfvars.json' "${provider} falls back to terraform.tfvars.json"
  done
}

test_override_order() {
  local provider=""
  local expected_override=""
  local last_line=""

  for provider in aws azure gcp; do
    reset_logs
    expected_override="${FIXTURES_DIR}/${provider}-root/overrides/custom.tfvars"
    run_wrapper "$provider" "${provider}-root" plan dev --tfvars overrides/custom.tfvars
    assert_eq "0" "$RUN_STATUS" "${provider} plan with override exits cleanly"
    last_line="$(last_log_line terraform)"
    case "$provider" in
      aws)
        [[ "$last_line" == *'-var-file=./env/dev/terraform.tfvars'*"${expected_override}"* ]] || fail 'aws keeps default tfvars before override'
        ;;
      azure)
        [[ "$last_line" == *'-var-file=./env/dev/terraform.tfvars'*"${expected_override}"* ]] || fail 'azure keeps default tfvars before override'
        ;;
      gcp)
        [[ "$last_line" == *'-var-file=./projects/dev/terraform.tfvars'*"${expected_override}"* ]] || fail 'gcp keeps default tfvars before override'
        ;;
    esac
  done
}

test_no_default_tfvars() {
  local provider=""
  local last_line=""

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" plan dev --no-default-tfvars --tfvars overrides/custom.tfvars
    assert_eq "0" "$RUN_STATUS" "${provider} plan with --no-default-tfvars exits cleanly"
    last_line="$(last_log_line terraform)"
    assert_contains "$last_line" 'overrides/custom.tfvars' "${provider} keeps the explicit override"
    assert_not_contains "$last_line" 'terraform.tfvars' "${provider} skips default tfvars when requested"
  done
}

test_summary_modes() {
  local provider=""

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" summ dev
    assert_eq "0" "$RUN_STATUS" "${provider} summary exits cleanly"
    assert_file_contains "${LOG_DIR}/tf-summarize.log" 'argv=' "${provider} summary calls tf-summarize"

    reset_logs
    run_wrapper "$provider" "${provider}-root" summ dev --summary-format pr
    assert_eq "0" "$RUN_STATUS" "${provider} PR summary exits cleanly"
    assert_contains "$RUN_STDOUT" '| Action | Address |' "${provider} PR summary prints markdown output"
  done
}

test_target_shortcut() {
  local provider=""
  local args=()
  local target_file="${FIXTURES_DIR}/target-test.tf"

  for provider in aws azure gcp; do
    reset_logs
    args=(apply dev "$target_file" --dry-run)
    if [[ "$provider" == 'aws' ]]; then
      args=(apply dev "$target_file" --cicd --dry-run)
    fi
    run_wrapper "$provider" "${provider}-root" "${args[@]}"
    assert_eq "0" "$RUN_STATUS" "${provider} file-target shortcut exits cleanly"
    assert_contains "$RUN_STDOUT" '-target=terraform_data.example' "${provider} derives the resource target"
    assert_contains "$RUN_STDOUT" '-target=module.example' "${provider} derives the module target"
  done
}

test_tlock_dry_run() {
  local provider=""

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" tlock noenv --dry-run
    assert_eq "0" "$RUN_STATUS" "${provider} tlock dry-run exits cleanly"
    assert_contains "$RUN_STDOUT" '-platform=windows_amd64' "${provider} tlock includes windows_amd64"
    assert_contains "$RUN_STDOUT" '-platform=darwin_amd64' "${provider} tlock includes darwin_amd64"
    assert_contains "$RUN_STDOUT" '-platform=darwin_arm64' "${provider} tlock includes darwin_arm64"
    assert_contains "$RUN_STDOUT" '-platform=linux_amd64' "${provider} tlock includes linux_amd64"
    assert_contains "$RUN_STDOUT" '-platform=linux_arm64' "${provider} tlock includes linux_arm64"
  done
}

test_unlock_dry_run() {
  local provider=""
  local lock_log="${FIXTURES_DIR}/lock-error.log"

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" unlock noenv --lock-id test-lock-id --dry-run
    assert_eq "0" "$RUN_STATUS" "${provider} unlock dry-run exits cleanly"
    assert_contains "$RUN_STDOUT" 'terraform force-unlock -force test-lock-id' "${provider} unlock dry-run prints the force-unlock command"

    reset_logs
    run_wrapper "$provider" "${provider}-root" unlock noenv --from-log "$lock_log" --dry-run
    assert_eq "0" "$RUN_STATUS" "${provider} unlock --from-log dry-run exits cleanly"
    assert_contains "$RUN_STDOUT" 'terraform force-unlock -force fake-log-lock-id' "${provider} unlock reads the lock id from log"
  done
}

test_aws_legacy_yaml_account() {
  reset_logs
  run_wrapper aws aws-root plan legacy --cicd
  assert_eq "0" "$RUN_STATUS" "aws legacy yaml_account plan exits cleanly"
  assert_file_contains "${LOG_DIR}/terraform.log" '-var=account_key=legacy' 'aws legacy yaml_account passes account_key'
}

test_summary_requires_tool() {
  reset_logs
  run_wrapper_without_summary azure azure-root summ dev
  assert_eq "1" "$RUN_STATUS" "azure summary without tf-summarize fails"
  assert_contains "$RUN_STDERR" 'Missing required binary: tf-summarize' 'azure summary reports the missing tf-summarize binary'
}

test_doctor_and_debug_bundle() {
  local provider=""
  local fixture_root=""

  for provider in aws azure gcp; do
    reset_logs
    run_wrapper "$provider" "${provider}-root" doctor dev
    assert_eq "0" "$RUN_STATUS" "${provider} doctor exits cleanly"
    assert_contains "$RUN_STDOUT" 'Doctor completed successfully' "${provider} doctor reports success"

    fixture_root="${FIXTURES_DIR}/${provider}-root"
    rm -rf "${fixture_root}/tmp/terraform-debug"
    run_wrapper "$provider" "${provider}-root" debug-bundle noenv
    assert_eq "0" "$RUN_STATUS" "${provider} debug-bundle exits cleanly"
    assert_path_exists "${fixture_root}/tmp/terraform-debug" "${provider} debug-bundle creates the debug directory"
  done
}

run_test() {
  local test_name="$1"

  printf 'ℹ️  Running %s\n' "$test_name"
  "$test_name"
  printf '✅ Passed %s\n' "$test_name"
}

main() {
  local tests=(
    test_script_metadata
    test_help_outputs
    test_clean_removes_local_artifacts
    test_noenv_dry_run_plan
    test_plan_with_env
    test_json_fallback
    test_override_order
    test_no_default_tfvars
    test_summary_modes
    test_target_shortcut
    test_tlock_dry_run
    test_unlock_dry_run
    test_aws_legacy_yaml_account
    test_summary_requires_tool
    test_doctor_and_debug_bundle
  )
  local test_name=""

  for test_name in "${tests[@]}"; do
    run_test "$test_name"
  done

  success "Terraform wrapper simulation suite completed"
  cleanup_runtime_artifacts
}

main "$@"
