#!/usr/bin/env bash
#
# Purpose: Terraform wrapper for Azure roots in this repository.
# Usage examples:
#   ./terraform.sh plan dev
#   ./terraform.sh apply dev target.tf --dry-run
#   ./terraform.sh summ noenv --summary-format pr
#
# Version: 1.13
# Change log:
# - 1.13 2026-05-03: align wrapper CLI, tfvars fallback, summaries, lock, unlock, doctor, and debug bundle.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly CLOUD_NAME="azure"
readonly LOCK_PLATFORMS=(
  "windows_amd64"
  "darwin_amd64"
  "darwin_arm64"
  "linux_amd64"
  "linux_arm64"
)

vers="1.13"

action="help"
env_arg=""
filetf=""
base_dir="$PWD"
backend_ini=""
backend_tfvars=""
subscription=""
dry_run=false
cicd_mode=false
skip_init=false
no_default_tfvars=false
summary_format="table"
summary_out=""
tfplan_path=""
unlock_force=false
unlock_lock_id=""
unlock_from_log=""
terraform_args=()
tfvars_overrides=()
resolved_tfvars=()
resolved_tfvars_paths=()
target_args=()
cleanup_paths=()
command_args=()

cleanup() {
  local exit_code=$?
  local cleanup_path=""

  if ((${#cleanup_paths[@]} > 0)); then
    for cleanup_path in "${cleanup_paths[@]}"; do
      if [[ -n "$cleanup_path" && -e "$cleanup_path" ]]; then
        rm -rf -- "$cleanup_path"
      fi
    done
  fi

  exit "$exit_code"
}

trap cleanup EXIT

info() {
  printf 'ℹ️  %s\n' "$*"
}

success() {
  printf '✅ %s\n' "$*"
}

warn() {
  printf '⚠️  %s\n' "$*"
}

die() {
  printf '❌ %s\n' "$*" >&2
  exit 1
}

add_cleanup_path() {
  cleanup_paths+=("$1")
}

print_cmd() {
  printf '%q ' "$@"
  printf '\n'
}

run_cmd() {
  if [[ "$dry_run" == true ]]; then
    printf '🧪 DRY-RUN: '
    print_cmd "$@"
    return 0
  fi

  "$@"
}

require_cmd() {
  local binary="$1"
  local context="${2:-}"

  if ! command -v "$binary" >/dev/null 2>&1; then
    if [[ -n "$context" ]]; then
      die "Missing required binary: ${binary} (${context})"
    fi
    die "Missing required binary: ${binary}"
  fi
}

usage() {
cat <<EOF
ℹ️  ${SCRIPT_NAME} version ${vers}

Usage:
  ./terraform.sh <action> <env|project|noenv> [file.tf] [wrapper options] [-- terraform args]
  ./terraform.sh help
  ./terraform.sh list
  ./terraform.sh clean

Examples:
  ./terraform.sh plan dev
  ./terraform.sh apply dev target.tf --dry-run
  ./terraform.sh summ noenv --summary-format pr
  ./terraform.sh tlock noenv -- -fs-mirror=/tmp/providers
  ./terraform.sh unlock dev --lock-id 00000000-0000-0000-0000-000000000000 --dry-run
  ./terraform.sh doctor dev
  ./terraform.sh debug-bundle dev

Base actions:
  clean         Remove local Terraform cache and plan artifacts
  help          Show this help
  list          List available environments
  doctor        Run non-destructive preflight checks
  debug-bundle  Collect a sanitized local debug bundle
  summ          Generate a Terraform plan summary with tf-summarize
  tlock         Generate or update the Terraform provider lock file
  unlock        Prepare or execute a safe terraform force-unlock

Wrapper options:
  --tfvars <file>            Add a var file override. Repeatable.
  --no-default-tfvars        Skip automatic terraform.tfvars lookup.
  --cicd, --ci               Skip interactive cloud-auth flows.
  --dry-run                  Print commands without executing them.
  --skip-init                Skip terraform init before action execution.
  --summary-format <format>  table|markdown|tree|separate-tree|json|json-sum|html|pr
  --tfplan <file>            Path used by summ for the generated plan.
  --summary-out <file>       Save tf-summarize output when supported.
  --lock-id <id>             Lock id used by unlock.
  --from-log <file>          Extract the lock id from a Terraform log.
  --force                    Skip wrapper confirmation for unlock.

Compatibility notes:
  noenv         Literal value that skips env-specific backend and cloud auth
  tflist        Optional compatibility action; requires a preinstalled tflist binary
  *             Any other action is passed to terraform
EOF
}

parse_cli() {
  if [[ $# -eq 0 ]]; then
    action="help"
    return 0
  fi

  action="$1"
  shift

  case "$action" in
    help|-h|\?|clean|list)
      ;;
    *)
      if [[ $# -eq 0 ]]; then
        die "Missing env/project argument. Use 'noenv' to skip environment resolution."
      fi
      env_arg="$1"
      shift
      if [[ $# -gt 0 && "$1" != -* && "$1" == *.tf ]]; then
        filetf="$1"
        shift
      fi
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --cicd|--ci)
        cicd_mode=true
        ;;
      --dry-run)
        dry_run=true
        ;;
      --skip-init)
        skip_init=true
        ;;
      --no-default-tfvars)
        no_default_tfvars=true
        ;;
      --summary-format)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --summary-format"
        summary_format="$1"
        ;;
      --summary-format=*)
        summary_format="${1#*=}"
        ;;
      --tfplan)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --tfplan"
        tfplan_path="$1"
        ;;
      --tfplan=*)
        tfplan_path="${1#*=}"
        ;;
      --summary-out)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --summary-out"
        summary_out="$1"
        ;;
      --summary-out=*)
        summary_out="${1#*=}"
        ;;
      --tfvars)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --tfvars"
        tfvars_overrides+=("$1")
        ;;
      --tfvars=*)
        tfvars_overrides+=("${1#*=}")
        ;;
      --lock-id)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --lock-id"
        unlock_lock_id="$1"
        ;;
      --lock-id=*)
        unlock_lock_id="${1#*=}"
        ;;
      --from-log)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --from-log"
        unlock_from_log="$1"
        ;;
      --from-log=*)
        unlock_from_log="${1#*=}"
        ;;
      --force)
        unlock_force=true
        ;;
      --)
        shift
        if [[ $# -gt 0 ]]; then
          terraform_args+=("$@")
        fi
        break
        ;;
      *)
        terraform_args+=("$1")
        ;;
    esac
    shift
  done
}

validate_summary_format() {
  case "$summary_format" in
    table|markdown|tree|separate-tree|json|json-sum|html|pr)
      ;;
    *)
      die "Unsupported --summary-format '${summary_format}'"
      ;;
  esac
}

action_supports_target_shortcut() {
  case "$action" in
    plan|apply|destroy)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

validate_cli_combinations() {
  if [[ -n "$filetf" && ! -f "$filetf" ]]; then
    die "Target file '${filetf}' does not exist"
  fi

  if [[ "$summary_format" != "table" || -n "$summary_out" || -n "$tfplan_path" ]] && [[ "$action" != "summ" ]]; then
    die "Summary options are only supported with the 'summ' action"
  fi

  if [[ -n "$unlock_lock_id" || -n "$unlock_from_log" || "$unlock_force" == true ]] && [[ "$action" != "unlock" ]]; then
    die "Unlock options are only supported with the 'unlock' action"
  fi

  if [[ -n "$filetf" ]] && ! action_supports_target_shortcut; then
    die "The file-target shortcut is supported only for plan, apply, and destroy"
  fi

  if [[ "$action" == "summ" ]]; then
    validate_summary_format
  fi
}

read_ini_value() {
  local file_path="$1"
  local wanted_key="$2"

  awk -F= -v wanted_key="$wanted_key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == wanted_key) {
        value=substr($0, index($0, "=") + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        gsub(/^"/, "", value)
        gsub(/"$/, "", value)
        print value
        exit
      }
    }
  ' "$file_path"
}

resolve_env_context() {
  base_dir="$PWD"
  backend_ini=""
  backend_tfvars=""
  subscription=""

  if [[ "$env_arg" == "noenv" ]]; then
    return 0
  fi

  base_dir="./env/${env_arg}"
  backend_ini="${base_dir}/backend.ini"
  backend_tfvars="${base_dir}/backend.tfvars"

  [[ -d "$base_dir" ]] || die "Missing environment directory '${base_dir}'"
  [[ -f "$backend_ini" ]] || die "Missing ${backend_ini}"
  [[ -f "$backend_tfvars" ]] || die "Missing ${backend_tfvars}"

  subscription="$(read_ini_value "$backend_ini" "subscription")"
  [[ -n "$subscription" ]] || die "Missing subscription in ${backend_ini}"
}

configure_provider_context() {
  if [[ "$env_arg" == "noenv" ]]; then
    return 0
  fi

  require_cmd "az" "needed for Azure subscription checks"
  run_cmd az account set -s "$subscription"

  if [[ "$dry_run" == false ]] && ! az account show --query id --output tsv >/dev/null 2>&1; then
    die "Azure authentication validation failed for subscription '${subscription}'"
  fi

  export ARM_SUBSCRIPTION_ID="$subscription"
  export TF_VAR_subscription_id="${TF_VAR_subscription_id:-$subscription}"
}

resolve_override_path() {
  local candidate="$1"

  if [[ "$candidate" = /* ]]; then
    [[ -f "$candidate" ]] || die "Missing tfvars override '${candidate}'"
    printf '%s\n' "$candidate"
    return 0
  fi

  if [[ -f "${base_dir}/${candidate}" ]]; then
    printf '%s\n' "${base_dir}/${candidate}"
    return 0
  fi

  if [[ -f "$PWD/${candidate}" ]]; then
    printf '%s\n' "$PWD/${candidate}"
    return 0
  fi

  die "Missing tfvars override '${candidate}'"
}

action_uses_var_files() {
  case "$action" in
    plan|apply|destroy|refresh|console|summ)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

action_uses_init() {
  case "$action" in
    help|-h|\?|clean|list|doctor|debug-bundle|tlock|unlock|fmt|version)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

resolve_var_files() {
  local default_var_file=""
  local override=""
  local resolved_override=""

  resolved_tfvars=()
  resolved_tfvars_paths=()

  if ! action_uses_var_files; then
    return 0
  fi

  if [[ "$no_default_tfvars" == false ]]; then
    if [[ -f "${base_dir}/terraform.tfvars" ]]; then
      default_var_file="${base_dir}/terraform.tfvars"
    elif [[ -f "${base_dir}/terraform.tfvars.json" ]]; then
      default_var_file="${base_dir}/terraform.tfvars.json"
    else
      die "Missing default var file in ${base_dir}. Expected terraform.tfvars or terraform.tfvars.json"
    fi

    resolved_tfvars+=("-var-file=${default_var_file}")
    resolved_tfvars_paths+=("${default_var_file}")
  fi

  if ((${#tfvars_overrides[@]} > 0)); then
    for override in "${tfvars_overrides[@]}"; do
      resolved_override="$(resolve_override_path "$override")"
      resolved_tfvars+=("-var-file=${resolved_override}")
      resolved_tfvars_paths+=("${resolved_override}")
    done
  fi
}

ensure_initialized() {
  local init_args=("terraform" "init" "-reconfigure")

  if [[ "$skip_init" == true ]]; then
    info "Skipping terraform init because --skip-init was provided"
    return 0
  fi

  if [[ "$env_arg" != "noenv" ]]; then
    init_args+=("-backend-config=${backend_tfvars}")
  fi

  run_cmd "${init_args[@]}"
}

extract_targets_from_tf_file() {
  local line=""
  local resource_pattern='^[[:space:]]*resource[[:space:]]+"([^"]+)"[[:space:]]+"([^"]+)"'
  local module_pattern='^[[:space:]]*module[[:space:]]+"([^"]+)"'

  target_args=()

  [[ -f "$filetf" ]] || die "Target file '${filetf}' does not exist"

  while IFS= read -r line; do
    if [[ "$line" =~ $resource_pattern ]]; then
      target_args+=("-target=${BASH_REMATCH[1]}.${BASH_REMATCH[2]}")
      continue
    fi

    if [[ "$line" =~ $module_pattern ]]; then
      target_args+=("-target=module.${BASH_REMATCH[1]}")
    fi
  done < "$filetf"

  if ((${#target_args[@]} == 0)); then
    die "No resource or module targets could be derived from '${filetf}'"
  fi

  warn "Using -target derived from ${filetf}. Targeted runs can hide dependencies and should stay exceptional."
}

build_terraform_command() {
  local terraform_action="$1"

  command_args=("terraform" "$terraform_action")

  case "$terraform_action" in
    plan|apply|destroy|refresh|console)
      command_args+=("-compact-warnings")
      ;;
  esac

  if action_uses_var_files && ((${#resolved_tfvars[@]} > 0)); then
    command_args+=("${resolved_tfvars[@]}")
  fi

  if ((${#target_args[@]} > 0)); then
    command_args+=("${target_args[@]}")
  fi

  if ((${#terraform_args[@]} > 0)); then
    command_args+=("${terraform_args[@]}")
  fi
}

summary_format_args() {
  command_args=("tf-summarize")

  case "$summary_format" in
    table)
      ;;
    markdown|pr)
      command_args+=("-md")
      ;;
    tree)
      command_args+=("-tree")
      ;;
    separate-tree)
      command_args+=("-separate-tree")
      ;;
    json)
      command_args+=("-json")
      ;;
    json-sum)
      command_args+=("-json-sum")
      ;;
    html)
      command_args+=("-html")
      ;;
  esac

  if [[ -n "$summary_out" ]]; then
    command_args+=("-out=${summary_out}")
  fi
}

run_summary() {
  local plan_file=""
  local plan_log=""
  local plan_cmd=()
  local summarize_cmd=()

  require_cmd "terraform" "needed for summ"
  require_cmd "tf-summarize" "needed for summ"
  resolve_var_files
  ensure_initialized

  if [[ -n "$tfplan_path" ]]; then
    plan_file="$tfplan_path"
  else
    plan_file="$(mktemp "${TMPDIR:-/tmp}/${CLOUD_NAME}-summ-plan.XXXXXX")"
    add_cleanup_path "$plan_file"
  fi

  build_terraform_command "plan"
  plan_cmd=("${command_args[@]}" "-out=${plan_file}")

  if [[ "$summary_format" == "pr" && "$dry_run" == false ]]; then
    plan_log="$(mktemp "${TMPDIR:-/tmp}/${CLOUD_NAME}-summ-log.XXXXXX")"
    add_cleanup_path "$plan_log"
    if ! "${plan_cmd[@]}" >"$plan_log" 2>&1; then
      cat "$plan_log" >&2
      exit 1
    fi
  else
    run_cmd "${plan_cmd[@]}"
  fi

  summary_format_args
  summarize_cmd=("${command_args[@]}" "$plan_file")
  run_cmd "${summarize_cmd[@]}"
}

run_provider_lock() {
  local lock_cmd=("terraform" "providers" "lock")
  local platform=""

  for platform in "${LOCK_PLATFORMS[@]}"; do
    lock_cmd+=("-platform=${platform}")
  done
  if ((${#terraform_args[@]} > 0)); then
    lock_cmd+=("${terraform_args[@]}")
  fi

  run_cmd "${lock_cmd[@]}"
}

extract_lock_id_from_log() {
  local log_file="$1"

  [[ -f "$log_file" ]] || die "Lock log '${log_file}' does not exist"
  sed -n 's/.*ID:[[:space:]]*\([0-9A-Za-z-][0-9A-Za-z-]*\).*/\1/p' "$log_file" | head -n 1
}

probe_lock_id() {
  local probe_log=""
  local probe_plan=""
  local probe_cmd=()

  require_cmd "terraform" "needed for lock probing"

  probe_log="$(mktemp "${TMPDIR:-/tmp}/${CLOUD_NAME}-unlock-log.XXXXXX")"
  probe_plan="$(mktemp "${TMPDIR:-/tmp}/${CLOUD_NAME}-unlock-plan.XXXXXX")"
  add_cleanup_path "$probe_log"
  add_cleanup_path "$probe_plan"

  if [[ "$skip_init" == false ]]; then
    ensure_initialized
  fi

  resolve_var_files
  probe_cmd=("terraform" "plan" "-compact-warnings" "-refresh=false" "-lock-timeout=0s" "-out=${probe_plan}")
  if ((${#resolved_tfvars[@]} > 0)); then
    probe_cmd+=("${resolved_tfvars[@]}")
  fi
  if ((${#terraform_args[@]} > 0)); then
    probe_cmd+=("${terraform_args[@]}")
  fi

  if "${probe_cmd[@]}" >"$probe_log" 2>&1; then
    return 1
  fi

  extract_lock_id_from_log "$probe_log"
}

confirm_unlock() {
  local answer=""

  if [[ "$unlock_force" == true ]]; then
    return 0
  fi

  if [[ "$dry_run" == true ]]; then
    info "Dry-run skips the interactive unlock confirmation"
    return 0
  fi

  read -r -p "Type 'unlock' to continue: " answer
  [[ "$answer" == "unlock" ]] || die "Unlock aborted by user"
}

run_unlock() {
  local resolved_lock_id="$unlock_lock_id"
  local unlock_cmd=()

  if [[ -z "$resolved_lock_id" && -n "$unlock_from_log" ]]; then
    resolved_lock_id="$(extract_lock_id_from_log "$unlock_from_log")"
  fi

  if [[ -z "$resolved_lock_id" ]]; then
    resolved_lock_id="$(probe_lock_id || true)"
  fi

  if [[ -z "$resolved_lock_id" ]]; then
    die "Unable to determine a Terraform lock id. Repeat with --lock-id or --from-log."
  fi

  warn "Use terraform force-unlock only for locks you own or that are clearly orphaned."
  info "Cloud script: ${CLOUD_NAME}"
  info "Context: ${env_arg}"
  info "Lock id: ${resolved_lock_id}"
  info "Command: terraform force-unlock -force ${resolved_lock_id}"

  confirm_unlock

  unlock_cmd=("terraform" "force-unlock" "-force" "$resolved_lock_id")
  run_cmd "${unlock_cmd[@]}"
}

sanitize_key_value_file() {
  local input_file="$1"
  local output_file="$2"

  awk -F= '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      key=$1
      value=substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      lower=tolower(key)
      if (lower ~ /(secret|password|token|key|client_secret|access_key|private)/) {
        value="***"
      }
      print key "=" value
    }
  ' "$input_file" > "$output_file"
}

populate_debug_var_files() {
  local default_var_file=""
  local override=""

  resolved_tfvars_paths=()
  if [[ "$no_default_tfvars" == false ]]; then
    if [[ -f "${base_dir}/terraform.tfvars" ]]; then
      default_var_file="${base_dir}/terraform.tfvars"
    elif [[ -f "${base_dir}/terraform.tfvars.json" ]]; then
      default_var_file="${base_dir}/terraform.tfvars.json"
    fi
    if [[ -n "$default_var_file" ]]; then
      resolved_tfvars_paths+=("$default_var_file")
    fi
  fi

  if ((${#tfvars_overrides[@]} > 0)); then
    for override in "${tfvars_overrides[@]}"; do
      if [[ "$override" = /* && -f "$override" ]]; then
        resolved_tfvars_paths+=("$override")
      elif [[ -f "${base_dir}/${override}" ]]; then
        resolved_tfvars_paths+=("${base_dir}/${override}")
      elif [[ -f "$PWD/${override}" ]]; then
        resolved_tfvars_paths+=("$PWD/${override}")
      fi
    done
  fi
}

collect_debug_bundle() {
  local timestamp=""
  local bundle_dir=""
  local providers_file=""
  local workspace_file=""

  populate_debug_var_files
  timestamp="$(date +%Y%m%d%H%M%S)"
  bundle_dir="tmp/terraform-debug/${timestamp}-${CLOUD_NAME}-${env_arg}"
  mkdir -p "$bundle_dir"

  {
    printf 'cloud=%s\n' "$CLOUD_NAME"
    printf 'env=%s\n' "$env_arg"
    printf 'base_dir=%s\n' "$base_dir"
    printf 'backend_ini=%s\n' "$backend_ini"
    printf 'backend_tfvars=%s\n' "$backend_tfvars"
    printf 'subscription=%s\n' "$subscription"
    printf 'skip_init=%s\n' "$skip_init"
    printf 'dry_run=%s\n' "$dry_run"
  } > "${bundle_dir}/summary.txt"

  if ((${#resolved_tfvars_paths[@]} > 0)); then
    printf '%s\n' "${resolved_tfvars_paths[@]}" > "${bundle_dir}/var-files.txt"
  else
    printf 'No resolved var files\n' > "${bundle_dir}/var-files.txt"
  fi

  if [[ -n "$backend_ini" && -f "$backend_ini" ]]; then
    sanitize_key_value_file "$backend_ini" "${bundle_dir}/backend-summary.txt"
  fi
  if [[ -n "$backend_tfvars" && -f "$backend_tfvars" ]]; then
    sanitize_key_value_file "$backend_tfvars" "${bundle_dir}/backend-tfvars-summary.txt"
  fi

  if command -v terraform >/dev/null 2>&1; then
    terraform version > "${bundle_dir}/terraform-version.txt" 2>&1 || true
  else
    printf 'terraform not available\n' > "${bundle_dir}/terraform-version.txt"
  fi

  if [[ -d .terraform ]] && command -v terraform >/dev/null 2>&1; then
    providers_file="${bundle_dir}/terraform-providers.txt"
    workspace_file="${bundle_dir}/terraform-workspace.txt"
    terraform providers > "$providers_file" 2>&1 || printf 'terraform providers failed\n' > "$providers_file"
    terraform workspace show > "$workspace_file" 2>&1 || printf 'terraform workspace show failed\n' > "$workspace_file"
  fi

  success "Debug bundle created at ${bundle_dir}"
}

run_doctor() {
  local issues=0
  local default_var_file="${base_dir}/terraform.tfvars"
  local fallback_var_file="${base_dir}/terraform.tfvars.json"
  local override=""

  info "Running doctor for ${CLOUD_NAME} (${env_arg})"

  if command -v terraform >/dev/null 2>&1; then
    success "terraform available"
  else
    warn "terraform missing"
    issues=$((issues + 1))
  fi

  if [[ "$env_arg" == "noenv" ]]; then
    info "noenv mode: backend and cloud-auth checks are skipped"
    base_dir="$PWD"
  else
    if [[ -f "$backend_ini" ]]; then
      success "backend.ini found: ${backend_ini}"
    else
      warn "backend.ini missing"
      issues=$((issues + 1))
    fi

    if [[ -f "$backend_tfvars" ]]; then
      success "backend.tfvars found: ${backend_tfvars}"
    else
      warn "backend.tfvars missing"
      issues=$((issues + 1))
    fi

    if [[ -n "$subscription" ]]; then
      success "Subscription resolved: ${subscription}"
    else
      warn "Subscription missing in backend.ini"
      issues=$((issues + 1))
    fi

    if command -v az >/dev/null 2>&1; then
      success "az CLI available"
      if [[ "$cicd_mode" == true ]]; then
        info "CICD mode enabled: skipping Azure auth validation"
      elif az account show --query id --output tsv >/dev/null 2>&1; then
        success "Azure authentication looks valid"
      else
        warn "Azure authentication is not currently valid"
        issues=$((issues + 1))
      fi
    else
      warn "az CLI missing"
      issues=$((issues + 1))
    fi
  fi

  if [[ "$no_default_tfvars" == true ]]; then
    info "Default tfvars disabled by --no-default-tfvars"
  elif [[ -f "$default_var_file" ]]; then
    success "Default tfvars found: ${default_var_file}"
  elif [[ -f "$fallback_var_file" ]]; then
    success "Fallback tfvars found: ${fallback_var_file}"
  else
    warn "No default tfvars found under ${base_dir}"
    issues=$((issues + 1))
  fi

  if ((${#tfvars_overrides[@]} > 0)); then
    for override in "${tfvars_overrides[@]}"; do
      if [[ "$override" = /* && -f "$override" ]]; then
        success "Override tfvars found: ${override}"
      elif [[ -f "${base_dir}/${override}" || -f "$PWD/${override}" ]]; then
        success "Override tfvars found: ${override}"
      else
        warn "Override tfvars missing: ${override}"
        issues=$((issues + 1))
      fi
    done
  fi

  if [[ -d .terraform ]]; then
    success ".terraform directory present"
  else
    warn ".terraform directory not initialized"
  fi

  if [[ $issues -gt 0 ]]; then
    warn "Doctor found ${issues} issue(s)"
    return 1
  fi

  success "Doctor completed successfully"
}

clean_environment() {
  rm -rf .terraform
  rm -f tfplan
  rm -f tfplan.*
  success "Removed local Terraform artifacts"
}

list_env() {
  local found=false
  local env_dir=""
  local env_name=""

  info "Available environments:"

  for env_dir in ./env/*/; do
    [[ -d "$env_dir" ]] || continue
    if [[ -f "${env_dir}backend.ini" ]]; then
      env_name="$(basename "$env_dir")"
      printf '📁 %s\n' "$env_name"
      found=true
    fi
  done

  [[ "$found" == true ]] || die "No environments found"
}

run_tflist_compat() {
  require_cmd "terraform" "needed for tflist"
  require_cmd "tflist" "optional compatibility formatter"
  ensure_initialized
  if [[ "$dry_run" == true ]]; then
    printf '🧪 DRY-RUN: terraform state list | tflist\n'
    return 0
  fi
  terraform state list | tflist
}

run_generic_action() {
  require_cmd "terraform" "needed for action '${action}'"

  if action_uses_var_files; then
    resolve_var_files
  fi

  if action_uses_init; then
    ensure_initialized
  fi

  if [[ -n "$filetf" ]]; then
    extract_targets_from_tf_file
  fi

  build_terraform_command "$action"
  run_cmd "${command_args[@]}"
}

main() {
  parse_cli "$@"
  validate_cli_combinations

  case "$action" in
    help|-h|\?)
      usage
      return 0
      ;;
    clean)
      clean_environment
      return 0
      ;;
    list)
      list_env
      return 0
      ;;
  esac

  [[ -n "$env_arg" ]] || die "Missing env/project argument. Use 'noenv' to skip environment resolution."

  resolve_env_context

  case "$action" in
    doctor)
      run_doctor
      ;;
    debug-bundle)
      collect_debug_bundle
      ;;
    init)
      require_cmd "terraform" "needed for init"
      configure_provider_context
      ensure_initialized
      ;;
    summ)
      configure_provider_context
      run_summary
      ;;
    tlock)
      require_cmd "terraform" "needed for tlock"
      run_provider_lock
      ;;
    unlock)
      configure_provider_context
      run_unlock
      ;;
    tflist)
      configure_provider_context
      run_tflist_compat
      ;;
    *)
      configure_provider_context
      run_generic_action
      ;;
  esac
}

main "$@"
