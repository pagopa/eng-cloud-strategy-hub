#!/usr/bin/env bash
#
# Purpose: Terraform wrapper for roots that derive isolated S3 state keys from env/backend.dynamic.ini.
# Usage examples:
#   ./terraform.sh plan <scope>
#   ./terraform.sh apply <scope> --dry-run
#
# Required env/backend.dynamic.ini shape:
#   s3_bucket = "<state-bucket>"
#   aws_region = "<aws-region>"
#   aws_account_name = "<provider-context>"
#   s3_key_prefix = "<state-prefix>"
#   s3_key_suffix = "tfstate"
# aws_account_name is required as a metadata field, but its value is not validated
# or passed to the S3 backend. The generated s3_key is the complete S3 object path
# used to locate the Terraform state: <s3_key_prefix>/<scope>/<s3_key_suffix>.
# state_variable optionally names the Terraform variable receiving the scope when
# present in backend.dynamic.ini.
# It defaults to terraform_context_key and can be overridden explicitly with
# --state-variable.
#
# Version: 1.9
# Change log:
# - 1.9 2026-08-12: default the dynamic scope variable and isolate saved-plan apply.
# - 1.8 2026-08-11: make scope and Terraform variable selection context-agnostic.
# - 1.7 2026-08-11: make the Terraform scope variable explicit instead of inferring it from the backend prefix.
# - 1.6 2026-08-10: rename the lock inventory action to find-locks.
# - 1.5 2026-08-10: inventory dynamic S3 locks and bulk force-unlock by state key.
# - 1.4 2026-08-04: Decision Run UI (PREFLIGHT/WORK/VERDICT), MODE icons, aws account name.
# - 1.3 2026-07-23: require aws_account_name presence and document generated s3_key.
# - 1.2 2026-07-23: let the script own S3 key path separators.
# - 1.1 2026-07-23: require the s3_ prefix for bucket and key settings.
# - 1.0 2026-07-23: derive scoped state keys from env/backend.dynamic.ini.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
readonly CLOUD_NAME="aws"
readonly LOCK_PLATFORMS=(
  "windows_amd64"
  "darwin_amd64"
  "darwin_arm64"
  "linux_amd64"
  "linux_arm64"
)

vers="1.9"

action="help"
env_arg=""
filetf=""
base_dir="$PWD"
backend_ini=""
config_mode="noenv"
aws_profile=""
aws_region=""
aws_account_name=""
s3_bucket=""
state_variable_name="terraform_context_key"
state_variable_overridden=false
dry_run=false
cicd_mode=false
skip_init=false
debug_mode=false
no_default_tfvars=false
summary_format="table"
summary_out=""
tfplan_path=""
unlock_force=false
unlock_lock_id=""
unlock_from_log=""
lock_keys=()
lock_last_modified=()
lock_sizes=()
lock_ids=()
lock_operations=()
lock_whos=()
lock_versions=()
lock_created=()
lock_paths=()
lock_scopes=()
lock_errors=()
terraform_args=()
tfvars_overrides=()
resolved_tfvars=()
resolved_tfvars_paths=()
target_args=()
backend_args=()
backend_key_prefix=""
backend_key_suffix=""
cleanup_paths=()
command_args=()
CURRENT_PHASE=""
CURRENT_PHASE_STARTED_AT=0
RUN_STARTED_AT=0
FAILED_PHASE=""
FAILED_REASON=""
PREFLIGHT_PRINTED=false
CLEANUP_FAILED=false
readonly UI_WIDTH=78

debug_sanitize() {
  local value="${1:-}"

  value="${value//$'\n'/ }"
  value="${value//$'\r'/ }"
  value="${value// /_}"
  printf '%s' "$value" | sed 's/[^A-Za-z0-9._:@\/-]/_/g'
}

debug_log() {
  [[ "$debug_mode" == true ]] || return 0
  printf 'DEBUG %s\n' "$*" >&2
}

debug_command_result() {
  local command_name=""
  local operation=""
  local result="$3"
  local exit_code="$4"

  command_name="$(debug_sanitize "${1:-unknown}")"
  operation="$(debug_sanitize "${2:-unknown}")"

  debug_log "event=command command=${command_name} operation=${operation} result=${result} exit_code=${exit_code}"
}

debug_command_exit() {
  local exit_code="$1"
  local result="failed"

  if ((exit_code == 0)); then
    result="success"
  fi
  debug_command_result "$2" "$3" "$result" "$exit_code"
}

phase_timestamp() {
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    printf '%s\n' "$EPOCHREALTIME"
  else
    date +%s
  fi
}

phase_duration() {
  local start="${1:-$CURRENT_PHASE_STARTED_AT}"
  local now=""

  now="$(phase_timestamp)"
  if [[ "$now" == *.* || "$start" == *.* ]]; then
    awk -v start="$start" -v end="$now" 'BEGIN { printf "%.1f", end - start }'
  else
    printf '%d.0' "$((now - start))"
  fi
}

ui_pad_rule() {
  local left="$1"
  local right="${2:-}"
  local fill_len=0
  local fill=""

  fill_len=$((UI_WIDTH - ${#left} - ${#right} - 1))
  if ((fill_len < 2)); then
    fill_len=2
  fi
  printf -v fill '%*s' "$fill_len" ''
  fill="${fill// /─}"
  printf '%s%s %s\n' "$left" "$fill" "$right"
}

ui_section_line() {
  local text="$1"

  printf '%s\n' "$text"
}

print_run_header() {
  local root_label="$base_dir"

  printf '%s  ·  terraform-dynamic-states v%s\n' "$CLOUD_NAME" "$vers"
  printf '%s  ·  %s\n' "$action" "${env_arg:-noenv}"
  printf '%s\n' "$root_label"
}

run_mode_label() {
  local action_upper=""

  action_upper="$(printf '%s' "$action" | tr '[:lower:]' '[:upper:]')"
  if [[ "$dry_run" == true ]]; then
    printf '🧪  DRY-RUN  (%s)\n' "$action"
    if [[ "$action" == "find-locks" || "$action" == "unlock-all" ]]; then
      printf 'read-only S3 discovery enabled · no mutating commands executed\n'
    else
      printf 'commands printed only · nothing executed\n'
    fi
    return 0
  fi

  case "$action" in
    apply)
      printf '🚀  APPLY\n'
      printf 'writes to remote state · changes will be applied\n'
      ;;
    destroy)
      printf '🗑️  DESTROY\n'
      printf 'destructive · resources may be removed\n'
      ;;
    unlock)
      printf '🔓  UNLOCK\n'
      printf 'force-unlock · use only for locks you own\n'
      ;;
    find-locks)
      printf '🔐  LOCK INVENTORY\n'
      printf 'read-only · lists S3 native Terraform locks\n'
      ;;
    unlock-all)
      printf '🔓  BULK UNLOCK\n'
      printf 'destructive · use only for locks you own\n'
      ;;
    plan|summ)
      printf '🔎  PLAN\n'
      printf 'preview only · no changes applied\n'
      ;;
    *)
      printf '📖  %s\n' "$action_upper"
      printf 'utility / read path\n'
      ;;
  esac
}

print_preflight() {
  local state_key="—"
  local scope_label="${env_arg:-noenv}"
  local aws_name="${aws_account_name:-unknown}"
  local region_label="${aws_region:-—}"
  local inputs_label="none"
  local flags_label="none"
  local mode_line=""
  local mode_note=""
  local dynamic_input_name="$state_variable_name"
  local target_count=0
  local tfvars_count=0
  local flag_parts=()
  local joined_flags=""

  if [[ "$PREFLIGHT_PRINTED" == true ]]; then
    return 0
  fi
  PREFLIGHT_PRINTED=true

  if [[ "$RUN_STARTED_AT" == "0" ]]; then
    RUN_STARTED_AT="$(phase_timestamp)"
  fi

  print_run_header

  if [[ -n "$backend_key_prefix" && -n "$backend_key_suffix" && -n "$env_arg" && "$env_arg" != "noenv" ]]; then
    if [[ "$env_arg" == "all" && ( "$action" == "find-locks" || "$action" == "unlock-all" ) ]]; then
      state_key="${backend_key_prefix}/*/${backend_key_suffix}.tflock"
    else
      state_key="${backend_key_prefix}/${env_arg}/${backend_key_suffix}"
    fi
    if [[ -n "$s3_bucket" ]]; then
      state_key="s3://${s3_bucket}/${state_key}"
    fi
  fi

  tfvars_count="${#resolved_tfvars_paths[@]}"
  target_count="${#target_args[@]}"
  inputs_label="tfvars: ${tfvars_count}  ·  targets: ${target_count}"
  if [[ "$config_mode" == "dynamic_state" && "$env_arg" != "noenv" ]]; then
    inputs_label="${dynamic_input_name}  ·  ${inputs_label}"
  fi

  if [[ "$dry_run" == true ]]; then
    flag_parts+=("dry-run")
  fi
  if [[ "$skip_init" == true ]]; then
    flag_parts+=("skip-init")
  fi
  if [[ "$cicd_mode" == true ]]; then
    flag_parts+=("cicd")
  fi
  if [[ "$no_default_tfvars" == true ]]; then
    flag_parts+=("no-default-tfvars")
  fi
  if [[ "$debug_mode" == true ]]; then
    flag_parts+=("debug")
  fi
  if ((${#flag_parts[@]} > 0)); then
    joined_flags="$(printf '%s · ' "${flag_parts[@]}")"
    flags_label="${joined_flags% · }"
  fi

  {
    IFS= read -r mode_line || mode_line=""
    IFS= read -r mode_note || mode_note=""
  } < <(run_mode_label)

  ui_pad_rule "── PREFLIGHT "
  ui_section_line "WHERE"
  ui_section_line "  scope        ${scope_label}"
  ui_section_line "  state        ${state_key}"
  ui_section_line "  backend      ${backend_ini:-—}"
  ui_section_line ""
  ui_section_line "WITH"
  ui_section_line "  mode         ${config_mode}"
  ui_section_line "  aws account  ${aws_name}  ·  ${region_label}"
  ui_section_line "  inputs       ${inputs_label}"
  ui_section_line "  flags        ${flags_label}"
  ui_section_line ""
  ui_section_line "MODE"
  ui_section_line "  ${mode_line}"
  if [[ -n "$mode_note" ]]; then
    ui_section_line "      ${mode_note}"
  fi
}

work_start() {
  local name="$1"

  CURRENT_PHASE="$name"
  CURRENT_PHASE_STARTED_AT="$(phase_timestamp)"
  printf '\n'
  ui_pad_rule "── ${name} " "running"
}

work_end() {
  local status="$1"
  local detail="${2:-}"
  local duration=""
  local right=""

  duration="$(phase_duration)"
  case "$status" in
    ok)
      right="✅ ${duration}s"
      ;;
    fail)
      right="❌ ${duration}s"
      if [[ -z "$FAILED_PHASE" ]]; then
        FAILED_PHASE="${CURRENT_PHASE:-unknown}"
      fi
      if [[ -z "$FAILED_REASON" && -n "$detail" ]]; then
        FAILED_REASON="$detail"
      fi
      ;;
    skip)
      right="⏭️ skip"
      ;;
    dry-run)
      right="🧪 dry-run"
      ;;
    *)
      right="$status"
      ;;
  esac

  ui_pad_rule "── ${CURRENT_PHASE:-WORK} " "$right"
  if [[ "$status" == "fail" && -n "$detail" ]]; then
    printf 'reason  %s\n' "$detail" >&2
  elif [[ "$status" == "skip" && -n "$detail" ]]; then
    printf '        %s\n' "$detail"
  fi
  CURRENT_PHASE=""
  CURRENT_PHASE_STARTED_AT=0
}

work_run() {
  local name="$1"
  shift
  local exit_code=0

  work_start "$name"
  set +e
  run_cmd "$@"
  exit_code=$?
  set -e

  if ((exit_code == 0)); then
    if [[ "$dry_run" == true ]]; then
      work_end dry-run
    else
      work_end ok
    fi
    return 0
  fi

  work_end fail "${name} failed"
  return "$exit_code"
}

action_work_name() {
  printf '%s\n' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
}

print_verdict() {
  local ok="$1"
  local total=""

  if [[ "$RUN_STARTED_AT" == "0" ]]; then
    total="0.0"
  else
    total="$(phase_duration "$RUN_STARTED_AT")"
  fi

  ui_pad_rule "── VERDICT "
  if [[ "$ok" == true ]]; then
    ui_section_line "✅  SUCCESS                                             total  ${total}s"
  else
    ui_section_line "❌  FAILED                                              total  ${total}s"
    ui_section_line "failed at   ${FAILED_PHASE:-unknown}"
    if [[ -n "$FAILED_REASON" ]]; then
      ui_section_line "reason      ${FAILED_REASON}"
    fi
  fi
}

cleanup() {
  local exit_code=$?
  local cleanup_path=""
  local final_code="$exit_code"
  local ok=true

  if [[ -n "$CURRENT_PHASE" ]]; then
    FAILED_PHASE="${FAILED_PHASE:-$CURRENT_PHASE}"
    work_end fail "${FAILED_REASON:-phase interrupted}"
  fi

  work_start "CLEANUP"
  if ((${#cleanup_paths[@]} > 0)); then
    for cleanup_path in "${cleanup_paths[@]}"; do
      if [[ -z "$cleanup_path" ]]; then
        continue
      fi
      if [[ -e "$cleanup_path" ]]; then
        if ! rm -rf -- "$cleanup_path"; then
          warn "Failed to remove local artifact: ${cleanup_path}"
          CLEANUP_FAILED=true
        fi
      fi
    done
  fi

  if ((exit_code != 0)); then
    ok=false
    FAILED_PHASE="${FAILED_PHASE:-unknown}"
    FAILED_REASON="${FAILED_REASON:-workflow failed}"
    work_end fail
  elif [[ "$CLEANUP_FAILED" == true ]]; then
    ok=false
    final_code=1
    if [[ -z "$FAILED_PHASE" ]]; then
      FAILED_PHASE="CLEANUP"
    fi
    if [[ -z "$FAILED_REASON" ]]; then
      FAILED_REASON="failed to remove local artifacts"
    fi
    work_end fail "$FAILED_REASON"
  else
    work_end ok
  fi

  if [[ "$PREFLIGHT_PRINTED" == true ]]; then
    print_verdict "$ok"
  fi

  exit "$final_code"
}

trap cleanup EXIT

info() {
  printf 'ℹ️  %s\n' "$*"
}

scope_label() {
  case "$env_arg" in
    all)
      printf 'all scopes\n'
      ;;
    noenv)
      printf 'current root\n'
      ;;
    *)
      printf "scope '%s'\n" "$env_arg"
      ;;
  esac
}

progress_info() {
  local operation="$1"

  info "${operation} · $(scope_label)"
}

success() {
  printf '✅ %s\n' "$*"
}

warn() {
  printf '⚠️  %s\n' "$*"
}

die() {
  if [[ -z "$FAILED_PHASE" ]]; then
    FAILED_PHASE="${CURRENT_PHASE:-workflow}"
  fi
  if [[ -z "$FAILED_REASON" ]]; then
    FAILED_REASON="$*"
  fi
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
  local command_name="${1:-unknown}"
  local operation="${2:-unknown}"
  local exit_code=0

  if [[ "$dry_run" == true ]]; then
    printf '$ '
    print_cmd "$@"
    debug_command_result "$command_name" "$operation" "dry-run" 0
    return 0
  fi

  "$@" || exit_code=$?
  debug_command_exit "$exit_code" "$command_name" "$operation"
  if ((exit_code != 0)); then
    return "$exit_code"
  fi
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
  ./terraform.sh <action> <scope|noenv> [file.tf] [wrapper options] [terraform args]
  ./terraform.sh help
  ./terraform.sh list  # unavailable in dynamic backend mode
  ./terraform.sh clean

Examples:
  ./terraform.sh plan <scope>
  ./terraform.sh plan <scope> -lock="false"
  ./terraform.sh apply <scope> target.tf --dry-run
  ./terraform.sh summ noenv --summary-format pr
  ./terraform.sh tlock noenv -fs-mirror="/tmp/providers"
  ./terraform.sh unlock <scope> --lock-id 00000000-0000-0000-0000-000000000000 --dry-run
  ./terraform.sh find-locks all --cicd
  ./terraform.sh unlock-all all --cicd --dry-run
  ./terraform.sh doctor <scope>
  ./terraform.sh debug-bundle <scope>

Base actions:
  clean         Remove local Terraform cache and plan artifacts
  help          Show this help
  list          Unavailable: dynamic backend mode has no scope catalog
  doctor        Run non-destructive preflight checks
  debug-bundle  Collect a sanitized local debug bundle
  summ          Generate a Terraform plan summary with tf-summarize
  tlock         Generate or update the Terraform provider lock file
  unlock        Prepare or execute a safe terraform force-unlock
  find-locks    List S3 native Terraform locks for a scope or all scopes
  unlock-all    Force-unlock every listed S3 lock after confirmation

Wrapper options:
  --tfvars <file>            Add a var file override. Repeatable.
  --no-default-tfvars        Skip automatic terraform.tfvars lookup.
  --cicd, --ci               Skip interactive cloud-auth flows.
  --dry-run                  Print commands without executing them.
  --skip-init                Skip terraform init before action execution.
  --state-variable <name>    Override the dynamic scope Terraform variable.
  --debug                    Write sanitized structured debug events to stderr.
  --summary-format <format>  table|markdown|tree|separate-tree|json|json-sum|html|pr
  --tfplan <file>            Path used by summ for the generated plan.
  --summary-out <file>       Save tf-summarize output when supported.
  --lock-id <id>             Lock id used by unlock.
  --from-log <file>          Extract the lock id from a Terraform log.
  --force                    Skip wrapper confirmation for unlock or unlock-all.

Compatibility notes:
  env/backend.dynamic.ini is the only backend configuration for dynamic scope mode.
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
        die "Missing scope argument. Use 'noenv' to skip environment resolution."
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
      --state-variable)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --state-variable"
        state_variable_name="$1"
        state_variable_overridden=true
        ;;
      --state-variable=*)
        state_variable_name="${1#*=}"
        state_variable_overridden=true
        ;;
      --debug)
        debug_mode=true
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

validate_state_variable_name() {
  [[ -n "$state_variable_name" ]] || return 0

  if [[ ! "$state_variable_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    die "Invalid --state-variable '${state_variable_name}'; use a Terraform variable name"
  fi
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
  validate_state_variable_name

  if [[ -n "$filetf" && ! -f "$filetf" ]]; then
    die "Target file '${filetf}' does not exist"
  fi

  if [[ "$action" == "unlock-all" && "$skip_init" == true ]]; then
    die "unlock-all does not support --skip-init: the backend must be re-initialized for every state lock"
  fi

  if [[ "$summary_format" != "table" || -n "$summary_out" ]] && [[ "$action" != "summ" ]]; then
    die "Summary options are only supported with the 'summ' action"
  fi

  if [[ -n "$tfplan_path" && "$action" != "summ" && "$action" != "apply" ]]; then
    die "The --tfplan option is only supported with 'summ' and 'apply'"
  fi

  if [[ -n "$unlock_lock_id" || -n "$unlock_from_log" || "$unlock_force" == true ]] && [[ "$action" != "unlock" && "$action" != "unlock-all" ]]; then
    die "Unlock options are only supported with the 'unlock' or 'unlock-all' action"
  fi

  if [[ "$action" == "unlock-all" && ( -n "$unlock_lock_id" || -n "$unlock_from_log" ) ]]; then
    die "--lock-id and --from-log are not supported with 'unlock-all'"
  fi

  if [[ ( "$action" == "find-locks" || "$action" == "unlock-all" ) && "$env_arg" == "noenv" ]]; then
    die "The '${action}' action requires a dynamic backend scope or 'all'; 'noenv' is not supported"
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

ini_key_exists() {
  local file_path="$1"
  local wanted_key="$2"

  awk -F= -v wanted_key="$wanted_key" '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    {
      key=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      if (key == wanted_key) {
        found=1
        exit
      }
    }
    END { exit(found ? 0 : 1) }
  ' "$file_path"
}

load_backend_config_args() {
  local raw_key=""
  local raw_value=""
  local key=""
  local value=""
  local configured_state_variable=""

  backend_args=()
  s3_bucket="$(read_ini_value "$backend_ini" "s3_bucket")"
  backend_key_prefix="$(read_ini_value "$backend_ini" "s3_key_prefix")"
  backend_key_suffix="$(read_ini_value "$backend_ini" "s3_key_suffix")"
  aws_account_name="$(read_ini_value "$backend_ini" "aws_account_name")"

  if [[ "$state_variable_overridden" == false ]] && ini_key_exists "$backend_ini" "state_variable"; then
    configured_state_variable="$(read_ini_value "$backend_ini" "state_variable")"
    if [[ -n "$configured_state_variable" ]]; then
      state_variable_name="$configured_state_variable"
    fi
  fi

  [[ -n "$s3_bucket" ]] || die "Missing s3_bucket in ${backend_ini}"
  ini_key_exists "$backend_ini" "aws_account_name" \
    || die "Missing aws_account_name in ${backend_ini}"
  [[ -n "$backend_key_prefix" ]] || die "Missing s3_key_prefix in ${backend_ini}"
  [[ -n "$backend_key_suffix" ]] || die "Missing s3_key_suffix in ${backend_ini}"
  validate_state_variable_name
  [[ "$backend_key_prefix" != */ ]] || die "s3_key_prefix must not end with '/' in ${backend_ini}"
  [[ "$backend_key_suffix" != /* ]] || die "s3_key_suffix must not start with '/' in ${backend_ini}"

  while IFS='=' read -r raw_key raw_value; do
    key="$(printf '%s' "$raw_key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    value="$(printf '%s' "$raw_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')"

    if [[ -z "$key" || "$key" == \#* ]]; then
      continue
    fi

    case "$key" in
      aws_account_name|aws_profile|s3_key_prefix|s3_key_suffix|state_variable)
        continue
        ;;
      s3_bucket)
        key="bucket"
        ;;
      s3_key)
        die "Static s3_key is not supported in ${backend_ini}; use s3_key_prefix and s3_key_suffix"
        ;;
      bucket|key|key_prefix|key_suffix)
        die "Unsupported backend key '${key}' in ${backend_ini}; S3 backend keys must use the s3_ prefix"
        ;;
      aws_region)
        key="region"
        ;;
    esac

    backend_args+=("-backend-config=${key}=${value}")
  done < "$backend_ini"

  backend_args+=("-backend-config=key=${backend_key_prefix}/${env_arg}/${backend_key_suffix}")
}

resolve_env_context() {
  base_dir="$PWD"
  backend_ini=""
  config_mode="noenv"
  aws_profile=""
  aws_region=""
  aws_account_name=""
  s3_bucket=""
  backend_key_prefix=""
  backend_key_suffix=""
  backend_args=()

  if [[ "$env_arg" == "noenv" ]]; then
    return 0
  fi

  backend_ini="./env/backend.dynamic.ini"
  [[ -f "$backend_ini" ]] || die "Missing dynamic backend config: ${backend_ini}"

  config_mode="dynamic_state"

  load_backend_config_args
  aws_profile="$(read_ini_value "$backend_ini" "aws_profile")"
  aws_region="$(read_ini_value "$backend_ini" "aws_region")"
  if [[ -z "$aws_region" ]]; then
    aws_region="$(read_ini_value "$backend_ini" "region")"
  fi
  if [[ -z "$aws_region" ]]; then
    die "Missing aws_region/region in ${backend_ini}"
  fi
}

is_cicd_mode() {
  if [[ "$cicd_mode" == true ]]; then
    return 0
  fi

  case "${CI:-}" in
    1|true|TRUE|yes|YES)
      return 0
      ;;
  esac

  return 1
}

configure_execution_context() {
  if is_cicd_mode; then
    export TF_IN_AUTOMATION="${TF_IN_AUTOMATION:-1}"
    export TF_INPUT="${TF_INPUT:-0}"
    progress_info "Automation mode enabled"
  fi
}

configure_provider_context() {
  local sso_start_url=""
  local sso_session=""

  if [[ "$env_arg" == "noenv" ]]; then
    return 0
  fi

  export AWS_REGION="$aws_region"
  export AWS_DEFAULT_REGION="$aws_region"

  if [[ -n "$aws_profile" ]]; then
    export AWS_PROFILE="$aws_profile"
  fi

  if is_cicd_mode; then
    return 0
  fi

  if [[ -z "$aws_profile" ]]; then
    return 0
  fi

  require_cmd "aws" "needed for AWS credential checks"
  if ! aws configure list-profiles | grep -qx "$aws_profile"; then
    die "AWS profile '${aws_profile}' not found"
  fi

  if aws sts get-caller-identity --profile "$aws_profile" >/dev/null 2>&1; then
    return 0
  fi

  sso_start_url="$(aws configure get sso_start_url --profile "$aws_profile" 2>/dev/null || true)"
  sso_session="$(aws configure get sso_session --profile "$aws_profile" 2>/dev/null || true)"
  if [[ -z "$sso_start_url" && -z "$sso_session" ]]; then
    die "AWS credentials validation failed for profile '${aws_profile}'"
  fi

  if ! aws sso login --profile "$aws_profile" >/dev/null; then
    die "AWS SSO login failed for profile '${aws_profile}'"
  fi
  if ! aws sts get-caller-identity --profile "$aws_profile" >/dev/null 2>&1; then
    die "AWS credentials validation failed for profile '${aws_profile}'"
  fi
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

apply_uses_saved_plan() {
  local argument=""

  [[ "$action" == "apply" ]] || return 1
  [[ -n "$tfplan_path" ]] && return 0
  ((${#terraform_args[@]} > 0)) || return 1

  for argument in "${terraform_args[@]}"; do
    [[ "$argument" == -* ]] && continue
    return 0
  done

  return 1
}

action_uses_var_files() {
  if apply_uses_saved_plan; then
    return 1
  fi

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
    help|-h|\?|clean|list|doctor|debug-bundle|tlock|unlock|find-locks|unlock-all|fmt|version)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

require_default_var_file() {
  if [[ "$no_default_tfvars" == true ]]; then
    return 1
  fi

  if [[ "$config_mode" == "dynamic_state" ]]; then
    return 1
  fi

  return 0
}

resolve_var_files() {
  local global_var_file=""
  local default_var_file=""
  local scope_var_file=""
  local override=""
  local resolved_override=""

  resolved_tfvars=()
  resolved_tfvars_paths=()

  if ! action_uses_var_files; then
    return 0
  fi

  if [[ "$no_default_tfvars" == false ]]; then
    global_var_file="${base_dir}/env/terraform.tfvars"
    if [[ -f "$global_var_file" ]]; then
      resolved_tfvars+=("-var-file=${global_var_file}")
      resolved_tfvars_paths+=("${global_var_file}")
    fi

    if [[ "$config_mode" == "dynamic_state" ]]; then
      if [[ "$env_arg" == */* || "$env_arg" == *\\* ]]; then
        die "Dynamic scope '${env_arg}' cannot be used as a tfvars filename"
      fi
      scope_var_file="${base_dir}/env/${env_arg}-terraform.tfvars"
      if [[ -f "$scope_var_file" ]]; then
        resolved_tfvars+=("-var-file=${scope_var_file}")
        resolved_tfvars_paths+=("${scope_var_file}")
      fi
    else
      if [[ -f "${base_dir}/terraform.tfvars" ]]; then
        default_var_file="${base_dir}/terraform.tfvars"
      elif [[ -f "${base_dir}/terraform.tfvars.json" ]]; then
        default_var_file="${base_dir}/terraform.tfvars.json"
      elif [[ ! -f "$global_var_file" ]] && require_default_var_file; then
        die "Missing default var file in ${base_dir}. Expected terraform.tfvars or terraform.tfvars.json"
      fi

      if [[ -n "$default_var_file" ]]; then
        resolved_tfvars+=("-var-file=${default_var_file}")
        resolved_tfvars_paths+=("${default_var_file}")
      fi
    fi
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
  local exit_code=0

  work_start "INIT"
  if [[ "$skip_init" == true ]]; then
    work_end skip "--skip-init was provided"
    return 0
  fi

  progress_info "Terraform initialization"
  if [[ "$env_arg" != "noenv" ]]; then
    init_args+=("${backend_args[@]}")
  fi

  set +e
  run_cmd "${init_args[@]}"
  exit_code=$?
  set -e

  if ((exit_code == 0)); then
    if [[ "$dry_run" == true ]]; then
      work_end dry-run
    else
      work_end ok
    fi
    return 0
  fi

  work_end fail "terraform init failed"
  return "$exit_code"
}

extract_targets_from_tf_file() {
  local line=""
  local resource_pattern='^[[:space:]]*resource[[:space:]]+"([^"]+)"[[:space:]]+"([^"]+)"'
  local module_pattern='^[[:space:]]*module[[:space:]]+"([^"]+)"'

  target_args=()
  if [[ -z "$filetf" || ( "$action" == "apply" && -n "$tfplan_path" ) ]]; then
    return 0
  fi

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
  local arg=""

  command_args=("terraform" "$terraform_action")

  case "$terraform_action" in
    plan|apply|destroy|refresh|console)
      command_args+=("-compact-warnings")
      ;;
  esac

  if [[ "$terraform_action" == "apply" && -n "$tfplan_path" ]]; then
    if ((${#terraform_args[@]} > 0)); then
      for arg in "${terraform_args[@]}"; do
        [[ "$arg" == "-auto-approve" ]] && continue
        command_args+=("$arg")
      done
    fi
    command_args+=("$tfplan_path")
    return 0
  fi

  if [[ "$config_mode" == "dynamic_state" && "$env_arg" != "noenv" ]] && action_uses_var_files; then
    command_args+=("-var=${state_variable_name}=${env_arg}")
  fi

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
  local plan_exit_code=0

  require_cmd "terraform" "needed for summ"
  require_cmd "tf-summarize" "needed for summ"
  resolve_var_files
  print_preflight
  ensure_initialized

  if [[ -n "$tfplan_path" ]]; then
    plan_file="$tfplan_path"
  else
    plan_file="$(mktemp "${TMPDIR:-/tmp}/${CLOUD_NAME}-summ-plan.XXXXXX")"
    add_cleanup_path "$plan_file"
  fi

  build_terraform_command "plan"
  plan_cmd=("${command_args[@]}" "-out=${plan_file}")

  work_start "PLAN"
  progress_info "Generating Terraform plan"
  if [[ "$summary_format" == "pr" && "$dry_run" == false ]]; then
    plan_log="$(mktemp "${TMPDIR:-/tmp}/${CLOUD_NAME}-summ-log.XXXXXX")"
    add_cleanup_path "$plan_log"
    set +e
    "${plan_cmd[@]}" 2>&1 | tee "$plan_log"
    plan_exit_code="${PIPESTATUS[0]}"
    set -e
    if ((plan_exit_code == 0)); then
      work_end ok
    else
      work_end fail "terraform plan failed"
      return "$plan_exit_code"
    fi
  else
    set +e
    run_cmd "${plan_cmd[@]}"
    plan_exit_code=$?
    set -e
    if ((plan_exit_code == 0)); then
      if [[ "$dry_run" == true ]]; then
        work_end dry-run
      else
        work_end ok
      fi
    else
      work_end fail "terraform plan failed"
      return "$plan_exit_code"
    fi
  fi

  summary_format_args
  summarize_cmd=("${command_args[@]}" "$plan_file")
  work_run "SUMMARY" "${summarize_cmd[@]}"
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

  print_preflight
  progress_info "Updating Terraform provider locks"
  work_run "PROVIDER LOCK" "${lock_cmd[@]}"
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
  if [[ "$config_mode" == "dynamic_state" && "$env_arg" != "noenv" ]]; then
    probe_cmd+=("-var=${state_variable_name}=${env_arg}")
  fi
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

  print_preflight
  work_start "LOCK DISCOVERY"
  progress_info "Resolving Terraform lock id"
  if [[ -z "$resolved_lock_id" && -n "$unlock_from_log" ]]; then
    resolved_lock_id="$(extract_lock_id_from_log "$unlock_from_log")"
  fi

  if [[ -z "$resolved_lock_id" ]]; then
    resolved_lock_id="$(probe_lock_id || true)"
  fi

  if [[ -z "$resolved_lock_id" ]]; then
    work_end fail "Unable to determine a Terraform lock id"
    die "Unable to determine a Terraform lock id. Repeat with --lock-id or --from-log."
  fi

  info "Lock id: ${resolved_lock_id}"
  work_end ok

  warn "Use terraform force-unlock only for locks you own or that are clearly orphaned."
  info "Cloud script: ${CLOUD_NAME}"
  info "Context: ${env_arg}"
  info "Command: terraform force-unlock -force ${resolved_lock_id}"
  confirm_unlock

  unlock_cmd=("terraform" "force-unlock" "-force" "$resolved_lock_id")
  work_run "UNLOCK" "${unlock_cmd[@]}"
}

lock_scope_prefix() {
  if [[ "$env_arg" == "all" ]]; then
    printf '%s/\n' "$backend_key_prefix"
  else
    printf '%s/%s/%s.tflock\n' "$backend_key_prefix" "$env_arg" "$backend_key_suffix"
  fi
}

lock_scope_from_key() {
  local lock_key="$1"
  local relative_key="${lock_key#"${backend_key_prefix}"/}"
  local state_suffix="/${backend_key_suffix}.tflock"

  [[ "$relative_key" == *"$state_suffix" ]] || return 1
  relative_key="${relative_key%"$state_suffix"}"
  [[ -n "$relative_key" ]] || return 1
  printf '%s\n' "$relative_key"
}

reset_lock_inventory() {
  lock_keys=()
  lock_last_modified=()
  lock_sizes=()
  lock_ids=()
  lock_operations=()
  lock_whos=()
  lock_versions=()
  lock_created=()
  lock_paths=()
  lock_scopes=()
  lock_errors=()
}

append_lock_record() {
  lock_keys+=("$1")
  lock_last_modified+=("$2")
  lock_sizes+=("$3")
  lock_ids+=("$4")
  lock_operations+=("$5")
  lock_whos+=("$6")
  lock_versions+=("$7")
  lock_created+=("$8")
  lock_paths+=("$9")
  lock_scopes+=("${10}")
  lock_errors+=("${11}")
}

collect_lock_inventory() {
  local list_prefix=""
  local expected_key=""
  local object_listing=""
  local lock_rows=""
  local key=""
  local last_modified=""
  local size=""
  local lock_document=""
  local metadata=""
  local lock_id=""
  local operation=""
  local who=""
  local version=""
  local created=""
  local lock_path=""
  local scope=""
  local error=""
  local state_key=""
  local lock_count=0
  local lock_index=0
  local exit_code=0

  reset_lock_inventory
  list_prefix="$(lock_scope_prefix)"
  if [[ "$env_arg" != "all" ]]; then
    expected_key="$list_prefix"
  fi

  debug_log "event=inventory stage=list result=started scope=$(debug_sanitize "$env_arg") prefix=$(debug_sanitize "$list_prefix")"

  work_start "LOCK DISCOVERY"
  if [[ "$env_arg" == "all" ]]; then
    info "Searching Terraform locks under s3://${s3_bucket}/${list_prefix} · all scopes"
  else
    info "Searching Terraform locks for scope '${env_arg}' under s3://${s3_bucket}/${list_prefix}"
  fi
  set +e
  object_listing="$(aws s3api list-objects-v2 \
    --bucket "$s3_bucket" \
    --prefix "$list_prefix" \
    --output json 2>/dev/null)"
  exit_code=$?
  set -e
  debug_command_exit "$exit_code" "aws" "list-objects-v2"
  if ((exit_code != 0)); then
    debug_log "event=inventory stage=list result=failed"
    work_end fail "S3 lock listing failed"
    die "Unable to list S3 locks under s3://${s3_bucket}/${list_prefix}"
  fi

  set +e
  lock_rows="$(printf '%s\n' "$object_listing" | jq -r '
    .Contents[]?
    | select((.Key // "") | endswith(".tflock"))
    | [.Key, (.LastModified // "-"), ((.Size // 0) | tostring)]
    | @tsv
  ')"
  exit_code=$?
  set -e
  debug_command_exit "$exit_code" "jq" "parse-lock-listing"
  if ((exit_code != 0)); then
    debug_log "event=inventory stage=parse result=failed"
    work_end fail "S3 lock listing response was not valid JSON"
    die "Unable to parse the S3 lock listing response"
  fi

  if [[ -n "$expected_key" ]]; then
    lock_count="$(printf '%s\n' "$lock_rows" | awk -F '\t' -v expected_key="$expected_key" '$1 == expected_key { count++ } END { print count + 0 }')"
  else
    lock_count="$(printf '%s\n' "$lock_rows" | awk 'NF { count++ } END { print count + 0 }')"
  fi
  info "Found ${lock_count} Terraform lock(s); reading metadata"

  while IFS=$'\t' read -r key last_modified size; do
    [[ -n "$key" ]] || continue
    if [[ -n "$expected_key" && "$key" != "$expected_key" ]]; then
      continue
    fi

    scope=""
    error=""
    lock_id=""
    operation="-"
    who="-"
    version="-"
    created="-"
    lock_path="-"
    state_key="${key%.tflock}"
    lock_index=$((lock_index + 1))

    if ! scope="$(lock_scope_from_key "$key")"; then
      error="unsupported dynamic state key"
      scope="-"
      info "Reading lock metadata ${lock_index}/${lock_count} · unknown scope · ${state_key}"
    else
      info "Reading lock metadata ${lock_index}/${lock_count} · scope '${scope}' · ${state_key}"
      set +e
      lock_document="$(aws s3 cp "s3://${s3_bucket}/${key}" - --only-show-errors 2>/dev/null)"
      exit_code=$?
      set -e
      debug_command_exit "$exit_code" "aws" "cp"
      if ((exit_code != 0)); then
        error="unable to read lock metadata"
      fi
    fi

    if [[ -z "$error" ]]; then
      set +e
      metadata="$(printf '%s\n' "$lock_document" | jq -er '
      [.ID // "", (.Operation // "-"), (.Who // "-"), (.Version // "-"),
       (.Created // "-"), (.Path // "-")]
      | @tsv
      ')"
      exit_code=$?
      set -e
      debug_command_exit "$exit_code" "jq" "parse-lock-metadata"
      if ((exit_code != 0)); then
        error="invalid lock metadata JSON"
      else
      IFS=$'\t' read -r lock_id operation who version created lock_path <<< "$metadata"
      if [[ -z "$lock_id" ]]; then
        error="lock metadata does not contain an ID"
      fi
      fi
    fi

    append_lock_record \
      "$key" "$last_modified" "$size" "$lock_id" "$operation" "$who" \
      "$version" "$created" "$lock_path" "$scope" "$error"

    if [[ -n "$error" ]]; then
      debug_log "event=inventory stage=metadata state_key=$(debug_sanitize "$state_key") scope=$(debug_sanitize "$scope") lock_id=$(debug_sanitize "$lock_id") result=failed reason=$(debug_sanitize "$error")"
    else
      debug_log "event=inventory stage=metadata state_key=$(debug_sanitize "$state_key") scope=$(debug_sanitize "$scope") lock_id=$(debug_sanitize "$lock_id") result=success"
    fi
  done <<< "$lock_rows"

  debug_log "event=inventory stage=list result=success scope=$(debug_sanitize "$env_arg") count=${#lock_keys[@]}"
  work_end ok
}

print_lock_inventory() {
  local index=0
  local state_key=""

  printf 'LOCK INVENTORY\n'
  printf 'scope      s3://%s/%s\n' "$s3_bucket" "$(lock_scope_prefix)"
  printf 'count      %d\n' "${#lock_keys[@]}"

  if ((${#lock_keys[@]} == 0)); then
    info "No S3 Terraform lock files found"
    return 0
  fi

  for index in "${!lock_keys[@]}"; do
    state_key="${lock_keys[index]%.tflock}"
    printf '\nLOCK %d\n' "$((index + 1))"
    printf 's3 object  s3://%s/%s\n' "$s3_bucket" "${lock_keys[index]}"
    printf 'state key  %s\n' "$state_key"
    printf 'scope      %s\n' "${lock_scopes[index]}"
    printf 'updated    %s\n' "${lock_last_modified[index]}"
    printf 'size       %s bytes\n' "${lock_sizes[index]}"
    if [[ -n "${lock_errors[index]}" ]]; then
      printf 'metadata   %s\n' "${lock_errors[index]}"
      continue
    fi
    printf 'lock id    %s\n' "${lock_ids[index]}"
    printf 'operation  %s\n' "${lock_operations[index]}"
    printf 'who        %s\n' "${lock_whos[index]}"
    printf 'version    %s\n' "${lock_versions[index]}"
    printf 'created    %s\n' "${lock_created[index]}"
    printf 'lock path  %s\n' "${lock_paths[index]}"
  done
}

lock_inventory_has_errors() {
  local error=""

  for error in "${lock_errors[@]}"; do
    if [[ -n "$error" ]]; then
      return 0
    fi
  done
  return 1
}

run_find_locks() {
  require_cmd "aws" "needed for S3 lock inventory"
  require_cmd "jq" "needed to parse S3 lock metadata"

  print_preflight
  collect_lock_inventory
  work_start "LOCK INVENTORY"
  print_lock_inventory
  if lock_inventory_has_errors; then
    work_end fail "Some S3 locks could not be parsed"
    return 1
  fi
  work_end ok
}

confirm_unlock_all() {
  local answer=""
  local read_exit_code=0

  work_start "CONFIRMATION"

  if [[ "$unlock_force" == true ]]; then
    debug_log "event=bulk-unlock stage=confirmation result=skipped reason=force"
    work_end skip "--force was provided"
    return 0
  fi

  if [[ "$dry_run" == true ]]; then
    debug_log "event=bulk-unlock stage=confirmation result=skipped reason=dry-run"
    info "Dry-run skips the interactive bulk unlock confirmation"
    work_end dry-run
    return 0
  fi

  debug_log "event=bulk-unlock stage=confirmation result=prompted"
  set +e
  printf "Type 'unlock-all' exactly to continue (not yes): " >&2
  read -r answer
  read_exit_code=$?
  set -e
  if ((read_exit_code == 0)) && [[ "$answer" == "unlock-all" ]]; then
    debug_log "event=bulk-unlock stage=confirmation result=accepted"
    work_end ok
    return 0
  fi

  if ((read_exit_code == 0)); then
    debug_log "event=bulk-unlock stage=confirmation result=rejected reason=invalid-input"
  else
    debug_log "event=bulk-unlock stage=confirmation result=rejected reason=eof"
  fi
  die "Bulk unlock aborted: type 'unlock-all' exactly to continue"
}

configure_dynamic_backend_scope() {
  env_arg="$1"
  load_backend_config_args
}

run_unlock_all() {
  local index=0
  local failed_count=0
  local scope=""
  local state_key=""
  local total=0
  local init_exit_code=0
  local unlock_exit_code=0
  local unlock_cmd=()

  require_cmd "aws" "needed for S3 lock inventory"
  require_cmd "jq" "needed to parse S3 lock metadata"
  require_cmd "terraform" "needed for bulk force-unlock"

  print_preflight
  collect_lock_inventory
  work_start "LOCK INVENTORY"
  print_lock_inventory
  if lock_inventory_has_errors; then
    work_end fail "Some S3 locks could not be parsed"
    die "Bulk unlock stopped because one or more locks have unreadable metadata"
  fi
  work_end ok

  if ((${#lock_keys[@]} == 0)); then
    return 0
  fi

  total="${#lock_keys[@]}"
  warn "Bulk force-unlock will process ${#lock_keys[@]} state lock(s) sequentially."
  warn "Use only when every listed lock is yours or clearly orphaned."
  confirm_unlock_all

  for index in "${!lock_keys[@]}"; do
    scope="${lock_scopes[index]}"
    state_key="${lock_keys[index]%.tflock}"
    debug_log "event=bulk-unlock stage=lock attempt=$((index + 1))/${total} scope=$(debug_sanitize "$scope") state_key=$(debug_sanitize "$state_key") lock_id=$(debug_sanitize "${lock_ids[index]}") result=started"
    configure_dynamic_backend_scope "$scope"
    info "Force-unlocking ${scope} (${lock_ids[index]})"
    if ensure_initialized; then
      :
    else
      init_exit_code=$?
      debug_log "event=bulk-unlock stage=lock attempt=$((index + 1))/${total} scope=$(debug_sanitize "$scope") state_key=$(debug_sanitize "$state_key") lock_id=$(debug_sanitize "${lock_ids[index]}") result=failed exit_code=${init_exit_code}"
      failed_count=$((failed_count + 1))
      continue
    fi

    unlock_cmd=("terraform" "force-unlock" "-force" "${lock_ids[index]}")
    if work_run "UNLOCK ${scope}" "${unlock_cmd[@]}"; then
      debug_log "event=bulk-unlock stage=lock attempt=$((index + 1))/${total} scope=$(debug_sanitize "$scope") state_key=$(debug_sanitize "$state_key") lock_id=$(debug_sanitize "${lock_ids[index]}") result=success"
    else
      unlock_exit_code=$?
      debug_log "event=bulk-unlock stage=lock attempt=$((index + 1))/${total} scope=$(debug_sanitize "$scope") state_key=$(debug_sanitize "$state_key") lock_id=$(debug_sanitize "${lock_ids[index]}") result=failed exit_code=${unlock_exit_code}"
      failed_count=$((failed_count + 1))
    fi
  done

  if ((failed_count > 0)); then
    die "Bulk force-unlock failed for ${failed_count} lock(s)"
  fi
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
  local global_var_file=""
  local default_var_file=""
  local scope_var_file=""
  local override=""

  resolved_tfvars_paths=()
  if [[ "$no_default_tfvars" == false ]]; then
    global_var_file="${base_dir}/env/terraform.tfvars"
    if [[ -f "$global_var_file" ]]; then
      resolved_tfvars_paths+=("$global_var_file")
    fi

    if [[ "$config_mode" == "dynamic_state" ]]; then
      if [[ "$env_arg" == */* || "$env_arg" == *\\* ]]; then
        die "Dynamic scope '${env_arg}' cannot be used as a tfvars filename"
      fi
      scope_var_file="${base_dir}/env/${env_arg}-terraform.tfvars"
      if [[ -f "$scope_var_file" ]]; then
        resolved_tfvars_paths+=("$scope_var_file")
      fi
    elif [[ -f "${base_dir}/terraform.tfvars" ]]; then
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

  print_preflight
  work_start "DEBUG BUNDLE"
  progress_info "Collecting debug bundle"
  populate_debug_var_files
  timestamp="$(date +%Y%m%d%H%M%S)"
  bundle_dir="tmp/terraform-debug/${timestamp}-${CLOUD_NAME}-${env_arg}"
  mkdir -p "$bundle_dir"

  {
    printf 'cloud=%s\n' "$CLOUD_NAME"
    printf 'env=%s\n' "$env_arg"
    printf 'mode=%s\n' "$config_mode"
    printf 'base_dir=%s\n' "$base_dir"
    printf 'backend_ini=%s\n' "$backend_ini"
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

  info "Debug bundle created at ${bundle_dir}"
  work_end ok
}

run_doctor() {
  local issues=0
  local global_var_file="${base_dir}/env/terraform.tfvars"
  local default_var_file="${base_dir}/terraform.tfvars"
  local fallback_var_file="${base_dir}/terraform.tfvars.json"
  local scope_var_file=""
  local override=""

  print_preflight
  work_start "DOCTOR"
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
    if [[ -n "$backend_ini" && -f "$backend_ini" ]]; then
      success "backend config found: ${backend_ini}"
    else
      warn "backend config missing"
      issues=$((issues + 1))
    fi

    if [[ -n "$aws_region" ]]; then
      success "AWS region resolved: ${aws_region}"
    else
      warn "AWS region missing in backend config"
      issues=$((issues + 1))
    fi

    if command -v aws >/dev/null 2>&1; then
      success "aws CLI available"
      if [[ -n "$aws_profile" ]]; then
        if aws sts get-caller-identity --profile "$aws_profile" >/dev/null 2>&1; then
          success "AWS credentials valid for profile ${aws_profile}"
        else
          warn "AWS credentials are not currently valid for profile ${aws_profile}"
          issues=$((issues + 1))
        fi
      else
        warn "No aws_profile configured; credential validation skipped"
      fi
    else
      warn "aws CLI missing"
      issues=$((issues + 1))
    fi
  fi

  if [[ "$no_default_tfvars" == true ]]; then
    info "Default tfvars disabled by --no-default-tfvars"
  else
    if [[ -f "$global_var_file" ]]; then
      success "Global tfvars found: ${global_var_file}"
    fi

    if [[ "$config_mode" == "dynamic_state" ]]; then
      if [[ "$env_arg" == */* || "$env_arg" == *\\* ]]; then
        warn "Dynamic scope '${env_arg}' cannot be used as a tfvars filename"
        issues=$((issues + 1))
      else
        scope_var_file="${base_dir}/env/${env_arg}-terraform.tfvars"
        if [[ -f "$scope_var_file" ]]; then
          success "Scope tfvars found: ${scope_var_file}"
        elif [[ ! -f "$global_var_file" ]]; then
          info "Dynamic state mode: global and scope tfvars are optional"
        fi
      fi
    elif [[ -f "$default_var_file" ]]; then
      success "Default tfvars found: ${default_var_file}"
    elif [[ -f "$fallback_var_file" ]]; then
      success "Fallback tfvars found: ${fallback_var_file}"
    elif [[ ! -f "$global_var_file" ]]; then
      warn "No default tfvars found under ${base_dir}"
      issues=$((issues + 1))
    fi
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
    work_end fail "Doctor found ${issues} issue(s)"
    return 1
  fi

  work_end ok
}

clean_environment() {
  work_start "CLEAN"
  info "Removing local Terraform artifacts"
  rm -rf .terraform
  rm -f tfplan
  rm -f tfplan.*
  work_end ok
}

list_env() {
  die "Dynamic backend mode does not maintain a scope catalog"
}

run_tflist_compat() {
  require_cmd "terraform" "needed for tflist"
  require_cmd "tflist" "optional compatibility formatter"
  print_preflight
  ensure_initialized
  work_start "TFLIST"
  progress_info "Listing Terraform state"
  if [[ "$dry_run" == true ]]; then
    printf '$ terraform state list | tflist\n'
    work_end dry-run
    return 0
  fi
  terraform state list | tflist
  work_end ok
}

run_generic_action() {
  local work_name=""

  require_cmd "terraform" "needed for action '${action}'"

  if action_uses_var_files; then
    resolve_var_files
  fi

  if [[ -n "$filetf" ]]; then
    extract_targets_from_tf_file
  fi

  print_preflight

  if action_uses_init; then
    ensure_initialized
  fi

  build_terraform_command "$action"
  work_name="$(action_work_name "$action")"
  progress_info "Running Terraform ${action}"
  work_run "$work_name" "${command_args[@]}"
}

main() {
  parse_cli "$@"
  validate_cli_combinations
  configure_execution_context

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
      ;;
  esac

  [[ -n "$env_arg" ]] || die "Missing scope argument. Use 'noenv' to skip environment resolution."

  resolve_env_context
  RUN_STARTED_AT="$(phase_timestamp)"

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
      print_preflight
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
    find-locks)
      configure_provider_context
      run_find_locks
      ;;
    unlock-all)
      configure_provider_context
      run_unlock_all
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
