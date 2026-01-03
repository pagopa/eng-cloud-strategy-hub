#!/bin/bash
############################################################
# Terraform script for managing infrastructure on AWS
# md5: 065397c756f4c6a1ba29f44d1e00ef74
############################################################
# Global variables
# Version format x.y accepted
vers="1.12"
# Define functions
function clean_environment() {
  rm -rf .terraform
  rm tfplan 2>/dev/null
  echo "🧹 cleaned!"
}

function extract_resources() {
  TF_FILE=$1
  ENV=$2
  TARGETS=""

  if [ ! -f "$TF_FILE" ]; then
    echo "❌ File $TF_FILE does not exist."
    exit 1
  fi

  if [ ! -d "./env/$ENV" ]; then
    echo "❌ Directory ./env/$ENV does not exist."
    exit 1
  fi

  TMP_FILE=$(mktemp)
  grep -E '^resource|^module' $TF_FILE > $TMP_FILE

  while read -r line ; do
      TYPE=$(echo $line | cut -d '"' -f 1 | tr -d ' ')
      if [ "$TYPE" == "module" ]; then
          NAME=$(echo $line | cut -d '"' -f 2)
          TARGETS+=" -target=\"$TYPE.$NAME\""
      else
          NAME1=$(echo $line | cut -d '"' -f 2)
          NAME2=$(echo $line | cut -d '"' -f 4)
          TARGETS+=" -target=\"$NAME1.$NAME2\""
      fi
  done < $TMP_FILE

  rm $TMP_FILE

  echo "ℹ️  ./terraform.sh $action $ENV $TARGETS"
}

function help_usage() {
  echo "ℹ️  terraform.sh Version ${vers}"
  echo
  echo "ℹ️  Usage: ./script.sh [ACTION] [ENV] [OTHER OPTIONS]"
  echo "ℹ️  es. ACTION: init, apply, plan, etc."
  echo "ℹ️  es. ENV: dev, uat, prod, etc."
  echo "ℹ️  es. OTHER OPTIONS: --cicd --dry-run"
  echo
  echo "ℹ️  Available actions:"
  echo "🔹 clean         Remove .terraform* folders and tfplan files"
  echo "🔹 help          This help"
  echo "🔹 list          List every environment available"
  echo "🔹 summ          Generate summary of Terraform plan"
  echo "🔹 tlock         Generate or update the dependency lock file"
  echo "🔹 *             any terraform option"
}

function require_cmd() {
  local bin="$1"
  local ctx="$2"
  if [ -z "$(command -v "$bin")" ]; then
    if [ -n "$ctx" ]; then
      echo "❌ Missing required binary: $bin ($ctx)"
    else
      echo "❌ Missing required binary: $bin"
    fi
    exit 1
  fi
}

function run_cmd() {
  if [ "$dry_run" = true ]; then
    echo "🧪 DRY-RUN: $*"
    return 0
  fi
  "$@"
}

function configure_aws_profile() {
  if [ -z "$aws_profile" ]; then
    echo "ℹ️  No aws_profile configured, skipping AWS profile setup"
    return 0
  fi

  export AWS_PROFILE="$aws_profile"

  if [ "$cicd_mode" = true ]; then
    echo "🤖 CICD mode enabled: skipping local AWS profile checks and SSO login"
    return 0
  fi

  require_cmd "aws" "needed for AWS profile checks"
  if ! aws configure list-profiles | grep -qx "$aws_profile"; then
    echo "❌ AWS profile '$aws_profile' not found"
    exit 1
  fi

  sso_start_url=$(aws configure get sso_start_url --profile "$aws_profile")
  sso_session=$(aws configure get sso_session --profile "$aws_profile")
  if [ -z "$sso_start_url" ] && [ -z "$sso_session" ]; then
    echo "ℹ️  Profile '$aws_profile' is not SSO-based, skipping aws sso login"
    if ! aws sts get-caller-identity --profile "$aws_profile" >/dev/null; then
      echo "❌ AWS credentials validation failed for profile '$aws_profile'"
      exit 1
    fi
    echo "✅ AWS credentials validated for profile '$aws_profile'"
    return 0
  fi

  if aws sts get-caller-identity --profile "$aws_profile" >/dev/null; then
    echo "✅ AWS SSO session already valid for profile '$aws_profile'"
    return 0
  fi

  if ! aws sso login --profile "$aws_profile" >/dev/null; then
    echo "❌ AWS SSO login failed for profile '$aws_profile'"
    exit 1
  fi
  if ! aws sts get-caller-identity --profile "$aws_profile" >/dev/null; then
    echo "❌ AWS credentials validation failed for profile '$aws_profile'"
    exit 1
  fi
  echo "✅ AWS credentials validated for profile '$aws_profile'"
}

function init_terraform() {
  require_env
  run_cmd terraform init -reconfigure -backend-config="./env/$env/backend.tfvars"
}

function list_env() {
  if [ ! -d "./env" ]; then
    echo "❌ No environment directory found"
    exit 1
  fi

  env_list=$(ls -d ./env/*/ 2>/dev/null)
  if [ -z "$env_list" ]; then
    echo "❌ No environments found"
    exit 1
  fi

  echo "ℹ️  Available environments:"
  for env in $env_list; do
    env_name=$(echo "$env" | sed 's#./env/##;s#/##')
    echo "📁 $env_name"
  done
}

function require_env() {
  if [ -z "$env" ]; then
    echo "❌ ERROR: missing env. Usage: ./terraform.sh <action> <env> [options]"
    exit 1
  fi
}

function run_with_vars() {
  require_env
  run_cmd terraform "$action" -var-file="./env/$env/terraform.tfvars" -compact-warnings $other
}

function run_no_vars() {
  run_cmd terraform "$action" $other
}


function parse_tfplan_option() {
  # Create an array to contain arguments that do not start with '-tfplan='
  local other_args=()

  # Loop over all arguments
  for arg in "$@"; do
    # If the argument starts with '-tfplan=', extract the file name
    if [[ "$arg" =~ ^-tfplan= ]]; then
      echo "${arg#*=}"
    else
      # If the argument does not start with '-tfplan=', add it to the other_args array
      other_args+=("$arg")
    fi
  done

  # Print all arguments in other_args separated by spaces
  echo "${other_args[@]}"
}

function tfsummary() {
  local plan_file
  plan_file=$(parse_tfplan_option "$@")
  if [ -z "$plan_file" ]; then
    plan_file="tfplan"
  fi
  action="plan"
  other="-out=${plan_file}"
  run_with_vars
  if [ -n "$(command -v tf-summarize)" ]; then
    run_cmd tf-summarize -tree "${plan_file}"
  else
    echo "⚠️  tf-summarize is not installed"
  fi
  if [ "$plan_file" == "tfplan" ]; then
    rm $plan_file
  fi
}

# Check arguments number
if [ "$#" -lt 1 ]; then
  help_usage
  exit 0
fi

# Parse arguments
action=$1
env=$2
filetf=$3
shift 2
cicd_mode=false
dry_run=false
other_args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --cicd|--ci)
      cicd_mode=true
      shift
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --)
      shift
      other_args+=("$@")
      break
      ;;
    *)
      other_args+=("$1")
      shift
      ;;
  esac
done
other="${other_args[@]}"

case "$action" in
  help|-h|\?|clean|list)
    ;;
  *)
    require_cmd "terraform" "needed for action '$action'"
    ;;
esac

if [ -n "$env" ]; then
  backend_ini="./env/$env/backend.ini"
  if [ -f "$backend_ini" ]; then
    # shellcheck source=/dev/null
    source "$backend_ini"
  else
    echo "❌ Missing backend.ini for env '$env'"
    exit 1
  fi

  if [ -z "$aws_region" ]; then
    echo "❌ Missing aws_region in $backend_ini"
    exit 1
  fi

  configure_aws_profile

  export AWS_REGION="$aws_region"
  export AWS_DEFAULT_REGION="$aws_region"
fi

# Call appropriate function based on action
case $action in
  clean)
    clean_environment
    ;;
  ?|help|-h)
    help_usage
    ;;
  init)
    init_terraform
    ;;
  list)
    list_env
    ;;
  output|state|taint)
    init_terraform
    run_no_vars
    ;;
  summ)
    init_terraform
    tfsummary "$other"
    ;;
  tlock)
    run_cmd terraform providers lock -platform=windows_amd64 -platform=darwin_amd64 -platform=darwin_arm64 -platform=linux_amd64
    ;;
  *)
    if [ -n "$filetf" ] && [ -f "$filetf" ]; then
      extract_resources "$filetf" "$env"
    else
      init_terraform
      run_with_vars
    fi
    ;;
esac
