#!/usr/bin/env bash
#
# Purpose: Create or align an S3 bucket for Terraform remote state on AWS.
# Usage examples:
#   ./scripts/aws/aws-terraform-s3-state-creator.sh --region eu-south-1 --account-name sandbox --bucket my-tf-state
#   ./scripts/aws/aws-terraform-s3-state-creator.sh --region eu-south-1 --account-name sandbox --bucket my-tf-state --tag Environment=dev --yes
#   ./scripts/aws/aws-terraform-s3-state-creator.sh --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly SCRIPT_PATH="scripts/aws/aws-terraform-s3-state-creator.sh"

REGION=""
ACCOUNT_NAME=""
BUCKET_NAME=""
PROFILE=""
DRY_RUN=false
ASSUME_YES=false

declare -a USER_TAGS=()
declare -a DEFAULT_TAGS=()
declare -a AWS_CMD=()

CALLER_ARN=""
CALLER_ACCOUNT_ID=""
CALLER_ACCOUNT_NAME=""
BUCKET_MODE=""

operation_label() {
  if [[ "${BUCKET_MODE}" == "create" ]]; then
    printf '%s' 'CREATE'
    return
  fi

  printf '%s' 'UPDATE'
}

operation_emoji() {
  if [[ "${BUCKET_MODE}" == "create" ]]; then
    printf '%s' '🆕'
    return
  fi

  printf '%s' '♻️'
}

operation_plan_summary() {
  if [[ "${BUCKET_MODE}" == "create" ]]; then
    printf '%s' 'new bucket will be created before applying baseline controls'
    return
  fi

  printf '%s' 'existing bucket will be updated in place with baseline controls'
}

log_bucket_step() {
  log_info "[$(operation_emoji) $(operation_label)] $*"
}

log_info() {
  echo "ℹ️  $*"
}

log_success() {
  echo "✅ $*"
}

log_warn() {
  echo "⚠️  $*"
}

log_error() {
  echo "❌ $*" >&2
}

die() {
  log_error "$*"
  exit 1
}

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} [OPTIONS]

Create or align a secure S3 bucket for Terraform remote state.

Requirements: aws, jq

Options:
  --region <aws-region>         AWS region for bucket operations (required)
  --account-name <name>         Expected AWS account name (required)
  --bucket <bucket-name>        Target S3 bucket name (required)
  --profile <aws-profile>       Optional AWS CLI profile
  --tag <Key=Value>             Additional tag (repeatable)
  --dry-run                     Print planned actions without mutating S3 settings
  --yes                         Skip y/N confirmation prompt
  -h, --help                    Show this help message

Examples:
  ${SCRIPT_NAME} --region eu-south-1 --account-name sandbox --bucket my-tf-state
  ${SCRIPT_NAME} --region eu-south-1 --account-name sandbox --bucket my-tf-state --tag Environment=dev --yes
  ${SCRIPT_NAME} --region eu-south-1 --account-name sandbox --bucket my-tf-state --dry-run
EOF
}

require_command() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    die "Required command not found: ${cmd}"
  fi
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    usage
    exit 0
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
    --region)
      [[ $# -ge 2 ]] || die "Missing value for --region"
      REGION="$2"
      shift 2
      ;;
    --account-name)
      [[ $# -ge 2 ]] || die "Missing value for --account-name"
      ACCOUNT_NAME="$2"
      shift 2
      ;;
    --bucket)
      [[ $# -ge 2 ]] || die "Missing value for --bucket"
      BUCKET_NAME="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || die "Missing value for --profile"
      PROFILE="$2"
      shift 2
      ;;
    --tag)
      [[ $# -ge 2 ]] || die "Missing value for --tag"
      USER_TAGS+=("$2")
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --yes)
      ASSUME_YES=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      die "Unknown option: $1"
      ;;
    esac
  done
}

validate_args() {
  [[ -n "${REGION}" ]] || die "--region is required"
  [[ -n "${ACCOUNT_NAME}" ]] || die "--account-name is required"
  [[ -n "${BUCKET_NAME}" ]] || die "--bucket is required"

  if [[ "${BUCKET_NAME}" =~ [A-Z] ]]; then
    die "Bucket name must be lowercase"
  fi

  validate_bucket_name

  local user_tag
  if [[ ${#USER_TAGS[@]} -gt 0 ]]; then
    for user_tag in "${USER_TAGS[@]}"; do
      validate_tag_format "${user_tag}"
    done
  fi
}

validate_bucket_name() {
  if [[ ${#BUCKET_NAME} -lt 3 || ${#BUCKET_NAME} -gt 63 ]]; then
    die "Bucket name is not a valid S3 bucket name"
  fi

  if [[ ! "${BUCKET_NAME}" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9]$ ]]; then
    die "Bucket name is not a valid S3 bucket name"
  fi

  if [[ "${BUCKET_NAME}" == *..* || "${BUCKET_NAME}" == *.-* || "${BUCKET_NAME}" == *-.* ]]; then
    die "Bucket name is not a valid S3 bucket name"
  fi

  if [[ "${BUCKET_NAME}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    die "Bucket name is not a valid S3 bucket name"
  fi

  if [[ "${BUCKET_NAME}" == xn--* || "${BUCKET_NAME}" == sthree-* || "${BUCKET_NAME}" == amzn-s3-demo-* ]]; then
    die "Bucket name is not a valid S3 bucket name"
  fi

  if [[ "${BUCKET_NAME}" == *-s3alias || "${BUCKET_NAME}" == *--ol-s3 || "${BUCKET_NAME}" == *.mrap || "${BUCKET_NAME}" == *--x-s3 || "${BUCKET_NAME}" == *--table-s3 ]]; then
    die "Bucket name is not a valid S3 bucket name"
  fi
}

validate_tag_format() {
  local tag_pair="$1"
  local key_part="${tag_pair%%=*}"
  local value_part="${tag_pair#*=}"

  if [[ "${tag_pair}" != *"="* ]]; then
    die "Invalid --tag format '${tag_pair}'. Expected Key=Value"
  fi

  if [[ -z "${key_part}" ]]; then
    die "Invalid --tag format '${tag_pair}'. Key cannot be empty"
  fi

  if [[ -z "${value_part}" ]]; then
    die "Invalid --tag format '${tag_pair}'. Value cannot be empty"
  fi
}

build_aws_cmd() {
  AWS_CMD=(aws)
  if [[ -n "${PROFILE}" ]]; then
    AWS_CMD+=(--profile "${PROFILE}")
  fi
  AWS_CMD+=(--region "${REGION}")
}

aws_query_text() {
  local service="$1"
  shift
  "${AWS_CMD[@]}" "${service}" "$@"
}

resolve_account_name() {
  local account_name=""

  account_name="$(aws_query_text organizations describe-account --account-id "${CALLER_ACCOUNT_ID}" --query 'Account.Name' --output text 2>/dev/null || true)"
  if [[ -n "${account_name}" && "${account_name}" != "None" ]]; then
    printf '%s' "${account_name}"
    return
  fi

  account_name="$(aws_query_text account get-account-information --query 'AccountName' --output text 2>/dev/null || true)"
  if [[ -n "${account_name}" && "${account_name}" != "None" ]]; then
    printf '%s' "${account_name}"
    return
  fi

  die "Unable to determine account name. Grant organizations:DescribeAccount or account:GetAccountInformation to verify --account-name"
}

collect_identity() {
  local sts_json
  sts_json="$(aws_query_text sts get-caller-identity --output json)"

  CALLER_ARN="$(printf '%s' "${sts_json}" | jq -er '.Arn')" || die "Unable to read caller ARN from sts get-caller-identity"
  CALLER_ACCOUNT_ID="$(printf '%s' "${sts_json}" | jq -er '.Account')" || die "Unable to read caller account ID from sts get-caller-identity"

  CALLER_ACCOUNT_NAME="$(resolve_account_name)"

  if [[ "${CALLER_ACCOUNT_NAME}" != "${ACCOUNT_NAME}" ]]; then
    die "Account name mismatch. Expected '${ACCOUNT_NAME}', found '${CALLER_ACCOUNT_NAME}'"
  fi
}

detect_bucket_mode() {
  local output

  if output="$(aws_query_text s3api head-bucket --bucket "${BUCKET_NAME}" --expected-bucket-owner "${CALLER_ACCOUNT_ID}" 2>&1)"; then
    BUCKET_MODE="update"
    return
  fi

  if echo "${output}" | grep -Eiq '403|forbidden|accessdenied'; then
    die "Bucket exists but is not accessible with current credentials: ${BUCKET_NAME}"
  fi

  if echo "${output}" | grep -Eiq '301|moved permanently'; then
    die "Bucket exists in a different region or endpoint context: ${BUCKET_NAME}"
  fi

  if echo "${output}" | grep -Eiq '404|not found|nosuchbucket'; then
    BUCKET_MODE="create"
    return
  fi

  die "Unable to determine bucket state for ${BUCKET_NAME}: ${output}"
}

build_default_tags() {
  local created_at
  created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  DEFAULT_TAGS=(
    "ScriptName=${SCRIPT_NAME}"
    "ManagedBy=manual"
    "CreatedByArn=${CALLER_ARN}"
    "CreatedAt=${created_at}"
    "Purpose=terraform-state"
    "StateBackend=s3"
    "Repository=eng-cloud-strategy-hub"
    "SourcePath=${SCRIPT_PATH}"
    "AutomationLevel=bootstrap"
    "DataClassification=internal"
  )
}

tag_pairs_to_json_array() {
  local json="[]"
  local tag_pair

  for tag_pair in "$@"; do
    local key_part="${tag_pair%%=*}"
    local value_part="${tag_pair#*=}"
    json="$(printf '%s' "${json}" | jq -c --arg key "${key_part}" --arg value "${value_part}" '. + [{Key: $key, Value: $value}]')"
  done

  printf '%s' "${json}"
}

get_existing_tag_set_json() {
  if [[ "${BUCKET_MODE}" == "create" ]]; then
    printf '[]'
    return
  fi

  local output

  if output="$(aws_query_text s3api get-bucket-tagging --bucket "${BUCKET_NAME}" --expected-bucket-owner "${CALLER_ACCOUNT_ID}" --output json 2>&1)"; then
    printf '%s' "${output}" | jq -c '.TagSet // []'
    return
  fi

  if echo "${output}" | grep -Eiq 'NoSuchTagSet|tagset does not exist'; then
    printf '[]'
    return
  fi

  die "Unable to read existing bucket tags for ${BUCKET_NAME}: ${output}"
}

build_tagging_payload() {
  local existing_tag_set_json
  local default_tags_json
  local user_tags_json
  local tagging_payload
  local tag_count

  existing_tag_set_json="$(get_existing_tag_set_json)"
  default_tags_json="$(tag_pairs_to_json_array "${DEFAULT_TAGS[@]}")"
  user_tags_json='[]'
  if [[ ${#USER_TAGS[@]} -gt 0 ]]; then
    user_tags_json="$(tag_pairs_to_json_array "${USER_TAGS[@]}")"
  fi

  tagging_payload="$(jq -cn \
    --argjson existing "${existing_tag_set_json}" \
    --argjson defaults "${default_tags_json}" \
    --argjson user "${user_tags_json}" \
    '{TagSet: ([ $existing[], $defaults[], $user[] ] | reduce .[] as $tag ({}; .[$tag.Key] = $tag.Value) | to_entries | map({Key: .key, Value: .value}) | sort_by(.Key))}')"

  tag_count="$(printf '%s' "${tagging_payload}" | jq '.TagSet | length')"
  if [[ ${tag_count} -gt 50 ]]; then
    die "Merged tag set exceeds S3 bucket limit of 50 tags"
  fi

  printf '%s' "${tagging_payload}"
}

render_report() {
  local planned_operation
  planned_operation="$(operation_label)"

  echo ""
  echo "============================================================"
  echo "Terraform State Bucket Plan"
  echo "============================================================"
  echo "Principal ARN : ${CALLER_ARN}"
  echo "Account ID    : ${CALLER_ACCOUNT_ID}"
  echo "Account Name  : ${CALLER_ACCOUNT_NAME}"
  echo "Region        : ${REGION}"
  echo "Bucket        : ${BUCKET_NAME}"
  echo "Operation     : $(operation_emoji) ${planned_operation} - $(operation_plan_summary)"
  echo "Dry Run       : ${DRY_RUN}"
  if [[ -n "${PROFILE}" ]]; then
    echo "Profile       : ${PROFILE}"
  fi
  echo ""
  echo "Security controls to apply:"
  echo "  - 🧾 Versioning enabled"
  echo "  - 🚫 Public access blocked at bucket level (ACL + bucket policy public exposure prevented)"
  echo "  - 👤 Object Ownership: BucketOwnerEnforced"
  echo "  - 🔐 Default encryption: SSE-S3 (AES256)"
  echo "  - 🌐 TLS-only bucket policy (preserve existing statements and deny non-HTTPS requests)"
  if [[ "${BUCKET_MODE}" == "create" ]]; then
    echo "  - 🧱 Object Lock capability enabled at creation"
  else
    echo "  - 🧱 Object Lock capability unchanged (cannot be enabled post-creation)"
  fi
  echo "  - 🏷️  Tags merged (existing + defaults + optional --tag values)"
  echo ""
  echo "Tags:"
  local tag_pair
  for tag_pair in "${DEFAULT_TAGS[@]}"; do
    echo "  - ${tag_pair}"
  done
  if [[ ${#USER_TAGS[@]} -gt 0 ]]; then
    for tag_pair in "${USER_TAGS[@]}"; do
      echo "  - ${tag_pair}"
    done
  fi
  echo ""
}

confirm_or_exit() {
  if [[ "${ASSUME_YES}" == true ]]; then
    log_bucket_step "Confirmation bypassed with --yes"
    return
  fi

  local answer
  read -r -p "Proceed with $(operation_emoji) $(operation_label) for bucket ${BUCKET_NAME}? [y/N] " answer
  case "${answer}" in
  y | Y | yes | YES)
    log_bucket_step "Confirmed by operator"
    ;;
  *)
    log_warn "Operation cancelled"
    exit 0
    ;;
  esac
}

create_bucket_if_needed() {
  if [[ "${BUCKET_MODE}" != "create" ]]; then
    return
  fi

  log_bucket_step "Creating bucket ${BUCKET_NAME} in ${REGION} with Object Lock capability"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api create-bucket with object lock capability"
    return
  fi

  if [[ "${REGION}" == "us-east-1" ]]; then
    aws_query_text s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --object-lock-enabled-for-bucket
  else
    aws_query_text s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --create-bucket-configuration "LocationConstraint=${REGION}" \
      --object-lock-enabled-for-bucket
  fi
}

apply_versioning() {
  log_bucket_step "Ensuring versioning is enabled"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api put-bucket-versioning"
    return
  fi

  aws_query_text s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --expected-bucket-owner "${CALLER_ACCOUNT_ID}" \
    --versioning-configuration Status=Enabled
}

apply_public_access_block() {
  log_bucket_step "Ensuring public access is blocked"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api put-public-access-block"
    return
  fi

  aws_query_text s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --expected-bucket-owner "${CALLER_ACCOUNT_ID}" \
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
}

apply_ownership_controls() {
  log_bucket_step "Ensuring bucket owner enforced object ownership"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api put-bucket-ownership-controls"
    return
  fi

  aws_query_text s3api put-bucket-ownership-controls \
    --bucket "${BUCKET_NAME}" \
    --expected-bucket-owner "${CALLER_ACCOUNT_ID}" \
    --ownership-controls 'Rules=[{ObjectOwnership=BucketOwnerEnforced}]'
}

apply_default_encryption() {
  log_bucket_step "Ensuring default SSE-S3 encryption"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api put-bucket-encryption"
    return
  fi

  aws_query_text s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --expected-bucket-owner "${CALLER_ACCOUNT_ID}" \
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
}

empty_bucket_policy_json() {
  printf '{"Version":"2012-10-17","Statement":[]}'
}

build_tls_only_statement() {
  jq -cn --arg bucket "${BUCKET_NAME}" '{
    Sid: "DenyInsecureTransport",
    Effect: "Deny",
    Principal: "*",
    Action: "s3:*",
    Resource: ["arn:aws:s3:::" + $bucket, "arn:aws:s3:::" + $bucket + "/*"],
    Condition: {Bool: {"aws:SecureTransport": "false"}}
  }'
}

get_existing_bucket_policy_json() {
  if [[ "${BUCKET_MODE}" == "create" ]]; then
    empty_bucket_policy_json
    return
  fi

  local output
  local policy_text

  if ! output="$(aws_query_text s3api get-bucket-policy --bucket "${BUCKET_NAME}" --expected-bucket-owner "${CALLER_ACCOUNT_ID}" --output json 2>&1)"; then
    if echo "${output}" | grep -Eiq 'NoSuchBucketPolicy|policy does not exist'; then
      empty_bucket_policy_json
      return
    fi

    die "Unable to read existing bucket policy for ${BUCKET_NAME}: ${output}"
  fi

  policy_text="$(printf '%s' "${output}" | jq -er '.Policy // empty')" || die "Unable to parse existing bucket policy response for ${BUCKET_NAME}"
  if [[ -z "${policy_text}" ]]; then
    empty_bucket_policy_json
    return
  fi

  printf '%s' "${policy_text}" | jq -ce '.' || die "Existing bucket policy for ${BUCKET_NAME} is not valid JSON"
}

build_tls_only_policy() {
  local existing_policy_json
  local tls_statement_json

  existing_policy_json="$(get_existing_bucket_policy_json)"
  tls_statement_json="$(build_tls_only_statement)"

  printf '%s' "${existing_policy_json}" | jq -c --argjson tls_statement "${tls_statement_json}" '
    .Version = (.Version // "2012-10-17")
    | .Statement = ((.Statement // []) | if type == "array" then . else [.] end | map(select(.Sid != "DenyInsecureTransport")) + [$tls_statement])
  '
}

apply_bucket_policy() {
  log_bucket_step "Ensuring TLS-only bucket policy"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api put-bucket-policy"
    return
  fi

  local policy_json
  policy_json="$(build_tls_only_policy)"

  aws_query_text s3api put-bucket-policy \
    --bucket "${BUCKET_NAME}" \
    --expected-bucket-owner "${CALLER_ACCOUNT_ID}" \
    --policy "${policy_json}"
}

apply_tags() {
  log_bucket_step "Applying bucket tags"
  if [[ "${DRY_RUN}" == true ]]; then
    log_bucket_step "DRY-RUN: s3api put-bucket-tagging"
    return
  fi

  local tagging_payload
  tagging_payload="$(build_tagging_payload)"
  aws_query_text s3api put-bucket-tagging \
    --bucket "${BUCKET_NAME}" \
    --expected-bucket-owner "${CALLER_ACCOUNT_ID}" \
    --tagging "${tagging_payload}"
}

apply_configuration() {
  log_bucket_step "Starting bucket configuration flow"
  create_bucket_if_needed
  apply_versioning
  apply_public_access_block
  apply_ownership_controls
  apply_default_encryption
  apply_bucket_policy
  apply_tags
}

main() {
  parse_args "$@"
  validate_args
  require_command aws
  require_command jq
  build_aws_cmd

  collect_identity
  detect_bucket_mode
  build_default_tags

  render_report
  confirm_or_exit

  apply_configuration

  if [[ "${DRY_RUN}" == true ]]; then
    log_success "Dry run completed for $(operation_emoji) $(operation_label). No AWS mutations executed"
  else
    log_success "$(operation_emoji) $(operation_label) completed. Bucket ${BUCKET_NAME} is configured for Terraform state"
  fi

  log_info "Object Lock default retention is intentionally not configured"
  log_info "Use Terraform backend use_lockfile=true with this bucket as needed"
}

main "$@"
