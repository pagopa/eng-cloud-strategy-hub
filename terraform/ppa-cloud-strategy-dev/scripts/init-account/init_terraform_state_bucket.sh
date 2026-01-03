#!/usr/bin/env bash
# Bootstrap an S3 bucket for Terraform state (SSE-S3, versioning, public access block).
# Example:
#   ./init_terraform_state_bucket.sh --profile pagopa-cloud-strategy-dev-fulladmin --region eu-south-1 --project-name eng-cloud-strategy-hub
set -euo pipefail

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found. Install it and configure credentials."
  exit 1
fi

require_non_empty() {
  local value="$1"
  local label="$2"
  if [ -z "${value}" ]; then
    echo "ERROR: ${label} is required."
    exit 1
  fi
}

usage() {
  echo "Usage: $0 --profile <aws_profile> --region <aws_region> --project-name <project_name>"
  exit 1
}

AWS_PROFILE=""
AWS_REGION=""
PROJECT_NAME=""

while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      AWS_PROFILE="${2:-}"
      shift 2
      ;;
    --region)
      AWS_REGION="${2:-}"
      shift 2
      ;;
    --project-name)
      PROJECT_NAME="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unknown argument '$1'"
      usage
      ;;
  esac
done

require_non_empty "${AWS_PROFILE}" "AWS profile name"
require_non_empty "${AWS_REGION}" "AWS region"
require_non_empty "${PROJECT_NAME}" "Project name"

normalize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd 'a-z0-9-'
}

AWS_REGION_NORM=$(normalize "${AWS_REGION}")
PROJECT_NAME_NORM=$(normalize "${PROJECT_NAME}")

# S3 bucket name
BUCKET_NAME="terraform-state-${PROJECT_NAME_NORM}-${AWS_REGION_NORM}"

echo "🔎 Bucket name: ${BUCKET_NAME}"

export AWS_PROFILE

echo "✅ Using AWS profile: ${AWS_PROFILE}"
echo "🔐 Verifying credentials..."
aws sts get-caller-identity >/dev/null

echo "🪣 Ensuring bucket exists..."
if aws s3api head-bucket --bucket "${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "ℹ️  Bucket ${BUCKET_NAME} already exists."
else
  if [ "${AWS_REGION_NORM}" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION_NORM}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET_NAME}" \
      --region "${AWS_REGION_NORM}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION_NORM}"
  fi
fi

echo "🔒 Applying public access block..."
aws s3api put-public-access-block \
  --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "🧾 Enabling versioning..."
aws s3api put-bucket-versioning \
  --bucket "${BUCKET_NAME}" \
  --versioning-configuration Status=Enabled

echo "🔐 Enabling default encryption (SSE-S3)..."
aws s3api put-bucket-encryption \
  --bucket "${BUCKET_NAME}" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "✅ Bucket ready."
echo "Use these backend values:"
echo "  bucket = ${BUCKET_NAME}"
echo "  region = ${AWS_REGION_NORM}"
