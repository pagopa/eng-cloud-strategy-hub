#!/usr/bin/env bash
############################################################
# Terraform script for managing infrastructure on AWS
# md5: 065397c756f4c6a1ba29f44d1e00ef74
############################################################
set -euo pipefail

# Global variables
# Version format x.y accepted
vers="1.12"

backend_ini=""
env_tfvars=""
config_mode=""
backend_args=()
terraform_args=()
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
  echo "ℹ️  es. ENV: payer, dev, uat, prod, etc."
  echo "ℹ️  es. OTHER OPTIONS: --cicd --dry-run plus Terraform args passed directly"
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
  if [ "$cicd_mode" = true ]; then
    echo "🤖 CICD mode enabled: skipping AWS profile setup"
    return 0
  fi

  if [ -z "$aws_profile" ]; then
    echo "ℹ️  No aws_profile configured, skipping AWS profile setup"
    return 0
  fi

  export AWS_PROFILE="$aws_profile"

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
  load_backend_config_args
  run_cmd terraform init -reconfigure "${backend_args[@]}"
}

function list_env() {
  echo "ℹ️  Available environments:"
  found=false

  for account_dir in ./*/; do
    [ -d "$account_dir" ] || continue
    if [ -f "${account_dir}backend.ini" ] && [ -f "${account_dir}authorization.yaml" ]; then
      env_name=$(echo "$account_dir" | sed 's#./##;s#/##')
      echo "📁 $env_name"
      found=true
    fi
  done

  for account_dir in ./env/*/; do
    [ -d "$account_dir" ] || continue
    if [ -f "${account_dir}backend.ini" ]; then
      env_name=$(basename "$account_dir")
      echo "📁 $env_name"
      found=true
    fi
  done

  if [ "$found" = false ]; then
    echo "❌ No environments found"
    exit 1
  fi
}

function require_env() {
  if [ -z "$env" ]; then
    echo "❌ ERROR: missing env. Usage: ./terraform.sh <action> <env> [options]"
    exit 1
  fi
}

function run_with_vars() {
  require_env
  if [ "$config_mode" = "tfvars_env" ]; then
    if [ -z "$env_tfvars" ]; then
      echo "❌ Missing ./env/$env/terraform.tfvars"
      exit 1
    fi

    run_cmd terraform "$action" -var-file="$env_tfvars" -compact-warnings "${terraform_args[@]}"
    return 0
  fi

  run_cmd terraform "$action" -var="account_key=$env" -compact-warnings "${terraform_args[@]}"
}

function run_no_vars() {
  run_cmd terraform "$action" "${terraform_args[@]}"
}

function action_uses_var_file() {
  case "$action" in
    import|output|state|taint|untaint)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

function action_uses_filetf_shortcut() {
  case "$action" in
    import|output|state|taint|untaint)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

function read_backend_value() {
  local file="$1"
  local lookup_key="$2"

  awk -F= -v lookup_key="$lookup_key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == lookup_key) {
        value=substr($0, index($0, "=") + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^"/, "", value)
        gsub(/"$/, "", value)
        print value
        exit
      }
    }
  ' "$file"
}

function resolve_env_files() {
  local account_backend="./$env/backend.ini"
  local account_yaml="./$env/authorization.yaml"
  local env_dir="./env/$env"
  local env_backend="$env_dir/backend.ini"
  local env_tfvars_file="$env_dir/terraform.tfvars"

  env_tfvars=""
  config_mode=""

  if [ -f "$account_backend" ] && [ -f "$account_yaml" ]; then
    backend_ini="$account_backend"
    config_mode="yaml_account"
    return 0
  fi

  if [ -f "$env_backend" ]; then
    backend_ini="$env_backend"
    config_mode="tfvars_env"
    if [ -f "$env_tfvars_file" ]; then
      env_tfvars="$env_tfvars_file"
    fi
    return 0
  fi

  if [ -f "$account_backend" ] && [ ! -f "$account_yaml" ]; then
    echo "❌ Missing $account_yaml"
    exit 1
  fi

  if [ -f "$account_yaml" ] && [ ! -f "$account_backend" ]; then
    echo "❌ Missing $account_backend"
    exit 1
  fi

  echo "❌ Missing env files for '$env'. Expected one of:"
  echo "   - $account_backend and $account_yaml"
  echo "   - $env_backend"
  exit 1
}

function load_backend_config_args() {
  backend_args=()

  while IFS='=' read -r raw_key raw_value; do
    key=$(echo "$raw_key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    value=$(echo "$raw_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')

    if [ -z "$key" ] || [[ "$key" == \#* ]]; then
      continue
    fi

    # Legacy alias used in this repository.
    if [ "$key" = "aws_region" ]; then
      key="region"
    fi

    # AWS profile is used locally by the wrapper script, not by the backend config.
    if [ "$key" = "aws_profile" ]; then
      continue
    fi

    backend_args+=("-backend-config=${key}=${value}")
  done < "$backend_ini"
}


function tfsummary() {
  local arg
  local plan_file=""
  local summary_args=()

  for arg in "${terraform_args[@]}"; do
    if [[ "$arg" =~ ^-tfplan= ]]; then
      plan_file="${arg#*=}"
    else
      summary_args+=("$arg")
    fi
  done

  if [ -z "$plan_file" ]; then
    plan_file="tfplan"
  fi

  action="plan"
  terraform_args=("${summary_args[@]}" "-out=${plan_file}")
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
shift

env=""
if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
  env=$1
  shift
fi

cicd_mode=false
dry_run=false
terraform_args=()
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
      terraform_args+=("$@")
      break
      ;;
    *)
      terraform_args+=("$1")
      shift
      ;;
  esac
done

filetf=""
if action_uses_filetf_shortcut && [ "${#terraform_args[@]}" -gt 0 ]; then
  candidate="${terraform_args[0]}"
  if [[ "$candidate" == *.tf ]] && [ -f "$candidate" ]; then
    filetf="$candidate"
    terraform_args=("${terraform_args[@]:1}")
  fi
fi

case "$action" in
  help|-h|\?|clean|list)
    ;;
  *)
    require_cmd "terraform" "needed for action '$action'"
    ;;
esac

if [ -n "$env" ]; then
  resolve_env_files

  aws_profile=$(read_backend_value "$backend_ini" "aws_profile")
  aws_region=$(read_backend_value "$backend_ini" "aws_region")
  if [ -z "$aws_region" ]; then
    aws_region=$(read_backend_value "$backend_ini" "region")
  fi
  if [ -z "$aws_region" ]; then
    echo "❌ Missing aws_region/region in $backend_ini"
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
  output|state|taint|untaint)
    init_terraform
    run_no_vars
    ;;
  summ)
    init_terraform
    tfsummary
    ;;
  tlock)
    run_cmd terraform providers lock -platform=windows_amd64 -platform=darwin_amd64 -platform=darwin_arm64 -platform=linux_amd64
    ;;
  *)
    if [ -n "$filetf" ] && [ -f "$filetf" ]; then
      extract_resources "$filetf" "$env"
    else
      init_terraform
      if action_uses_var_file; then
        run_with_vars
      else
        run_no_vars
      fi
    fi
    ;;
esac
