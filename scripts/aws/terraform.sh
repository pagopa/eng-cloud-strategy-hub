#!/usr/bin/env bash
#
# Purpose: Self-contained, project-agnostic Terraform wrapper.
# Usage examples:
#   ./terraform.sh plan
#   ./terraform.sh apply target.tf --dry-run
#   ./terraform.sh summ --summary-format pr
#
# Version: 2.0
# Change log:
# - 2.0 2026-08-11: remove project-specific context and make root resolution explicit and portable.
# - 1.14 2026-08-04: add Decision Run logging with preflight, work phases, cleanup, and verdict.
# - 1.13 2026-05-03: align wrapper CLI, tfvars fallback, summaries, lock, unlock, doctor, and debug bundle.

set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_NAME
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DEFAULT_TERRAFORM_ROOT="$SCRIPT_DIR"
if [[ "$(basename -- "$SCRIPT_DIR")" == "scripts" ]]; then
  DEFAULT_TERRAFORM_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd -P)"
fi
readonly SCRIPT_DIR
readonly DEFAULT_TERRAFORM_ROOT
readonly LOCK_PLATFORMS=(
  "windows_amd64"
  "darwin_amd64"
  "darwin_arm64"
  "linux_amd64"
  "linux_arm64"
)

vers="2.0"

action="help"
context_selector=""
filetf=""
root_override=""
base_dir="$DEFAULT_TERRAFORM_ROOT"
input_dir="$DEFAULT_TERRAFORM_ROOT"
backend_ini=""
aws_profile=""
aws_region=""
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
init_args=()
backend_args=()
tfvars_overrides=()
resolved_tfvars=()
resolved_tfvars_paths=()
target_args=()
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
  printf 'terraform v%s\n' "$vers"
  printf '%s\n' "$action"
  printf '%s\n' "$base_dir"
}

run_mode_label() {
  local action_upper=""

  action_upper="$(printf '%s' "$action" | tr '[:lower:]' '[:upper:]')"
  if [[ "$dry_run" == true ]]; then
    printf '🧪  DRY-RUN  (%s)\n' "$action"
    printf 'commands printed only · nothing executed\n'
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
  local inputs_label="none"
  local flags_label="none"
  local mode_line=""
  local mode_note=""
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

  tfvars_count="${#resolved_tfvars_paths[@]}"
  target_count="${#target_args[@]}"
  inputs_label="tfvars: ${tfvars_count}  ·  targets: ${target_count}"

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
  ui_section_line "  root         ${base_dir}"
  ui_section_line ""
  ui_section_line "WITH"
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
      FAILED_PHASE="${CURRENT_PHASE:-unknown}"
      if [[ -n "$detail" ]]; then
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
  local report_phase=""
  local report_reason=""

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
    report_phase="${FAILED_PHASE:-unknown}"
    report_reason="${FAILED_REASON:-workflow failed}"
    work_end fail "workflow failed"
    FAILED_PHASE="$report_phase"
    FAILED_REASON="$report_reason"
  elif [[ "$CLEANUP_FAILED" == true ]]; then
    ok=false
    final_code=1
    FAILED_PHASE="CLEANUP"
    FAILED_REASON="failed to remove local artifacts"
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

success() {
  printf '✅ %s\n' "$*"
}

warn() {
  printf '⚠️  %s\n' "$*"
}

die() {
  FAILED_PHASE="${CURRENT_PHASE:-${FAILED_PHASE:-workflow}}"
  FAILED_REASON="$*"
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
  local exit_code=0

  if [[ "$dry_run" == true ]]; then
    printf '$ '
    print_cmd "$@"
    return 0
  fi

  "$@" || exit_code=$?
  if ((exit_code != 0)); then
    FAILED_REASON="Command failed: $(printf '%q ' "$@")"
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
  ./terraform.sh <action> <environment-or-target> [target.tf] [wrapper options] [terraform args]
  ./terraform.sh help
  ./terraform.sh list
  ./terraform.sh clean

Examples:
  ./terraform.sh plan
  ./terraform.sh plan -lock="false"
  ./terraform.sh apply target.tf --dry-run
  ./terraform.sh summ --summary-format pr
  ./terraform.sh tlock -fs-mirror="/tmp/providers"
  ./terraform.sh unlock --lock-id 00000000-0000-0000-0000-000000000000 --dry-run
  ./terraform.sh doctor
  ./terraform.sh debug-bundle

Base actions:
  clean         Remove local Terraform cache and plan artifacts
  help          Show this help
  list          List Terraform workspaces
  doctor        Run non-destructive preflight checks
  debug-bundle  Collect a sanitized local debug bundle
  summ          Generate a Terraform plan summary with tf-summarize
  tlock         Generate or update the Terraform provider lock file
  unlock        Prepare or execute a safe terraform force-unlock

Wrapper options:
  --root <dir>               Run Terraform from this directory. Also supports TERRAFORM_ROOT.
  --tfvars <file>            Add a var file override. Repeatable.
  --no-default-tfvars        Skip automatic terraform.tfvars lookup.
  --cicd, --ci               Set Terraform automation environment variables.
  --dry-run                  Print commands without executing them.
  --skip-init                Skip terraform init before action execution.
  --init-arg <arg>           Add an argument to terraform init. Repeatable.
  --summary-format <format>  table|markdown|tree|separate-tree|json|json-sum|html|pr
  --tfplan <file>            Path used by summ for the generated plan.
  --summary-out <file>       Save tf-summarize output when supported.
  --lock-id <id>             Lock id used by unlock.
  --from-log <file>          Extract the lock id from a Terraform log.
  --force                    Skip wrapper confirmation for unlock.

Notes:
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
      if [[ $# -gt 0 && "$1" != -* && "$1" != *.tf ]]; then
        context_selector="$1"
        shift
      fi

      if [[ $# -gt 0 && "$1" != -* && "$1" == *.tf ]]; then
        filetf="$1"
        shift
      fi
      ;;
  esac

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --root)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --root"
        root_override="$1"
        ;;
      --root=*)
        root_override="${1#*=}"
        ;;
      --cicd|--ci)
        cicd_mode=true
        ;;
      --dry-run)
        dry_run=true
        ;;
      --skip-init)
        skip_init=true
        ;;
      --init-arg)
        shift
        [[ $# -gt 0 ]] || die "Missing value for --init-arg"
        init_args+=("$1")
        ;;
      --init-arg=*)
        init_args+=("${1#*=}")
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
        terraform_args+=("$@")
        break
        ;;
      *)
        terraform_args+=("$1")
        ;;
    esac
    shift
  done
}

resolve_terraform_root() {
  local candidate="${root_override:-${TERRAFORM_ROOT:-$DEFAULT_TERRAFORM_ROOT}}"

  [[ -d "$candidate" ]] || die "Terraform root '${candidate}' does not exist"
  base_dir="$(cd -- "$candidate" && pwd -P)"
  input_dir="$base_dir"
  cd -- "$base_dir" || die "Unable to enter Terraform root '${base_dir}'"
}

load_backend_config() {
  local key=""
  local value=""
  local backend_key=""

  backend_args=()
  aws_profile=""
  aws_region=""

  while IFS=$'\t' read -r key value; do
    backend_key="$key"
    case "$key" in
      profile|aws_profile)
        aws_profile="$value"
        backend_key="profile"
        ;;
      region|aws_region)
        aws_region="$value"
        backend_key="region"
        ;;
    esac
    backend_args+=("-backend-config=${backend_key}=${value}")
  done < <(
    awk -F= '
      function trim(value) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        return value
      }
      /^[[:space:]]*#/ { next }
      /^[[:space:]]*;/ { next }
      /^[[:space:]]*$/ { next }
      index($0, "=") == 0 { next }
      {
        key = trim($1)
        value = trim(substr($0, index($0, "=") + 1))
        sub(/^"/, "", value)
        sub(/"$/, "", value)
        if (key != "") {
          printf "%s\t%s\n", key, value
        }
      }
    ' "$backend_ini"
  )
}

configure_provider_context() {
  if [[ -n "$aws_profile" ]]; then
    export AWS_PROFILE="$aws_profile"
  fi
  if [[ -n "$aws_region" ]]; then
    export AWS_REGION="$aws_region"
    export AWS_DEFAULT_REGION="$aws_region"
  fi
}

resolve_context() {
  local direct_context_dir=""
  local direct_backend=""
  local environment_context_dir=""
  local environment_backend=""

  backend_ini=""
  backend_args=()
  aws_profile=""
  aws_region=""

  if [[ -z "$context_selector" ]]; then
    if [[ -f "${base_dir}/backend.ini" ]]; then
      backend_ini="${base_dir}/backend.ini"
    fi
  elif [[ "$context_selector" == "noenv" ]]; then
    return 0
  else
    direct_context_dir="${base_dir}/${context_selector}"
    direct_backend="${direct_context_dir}/backend.ini"
    environment_context_dir="${base_dir}/env/${context_selector}"
    environment_backend="${environment_context_dir}/backend.ini"

    if [[ -f "$direct_backend" ]]; then
      base_dir="$direct_context_dir"
      input_dir="$direct_context_dir"
      backend_ini="$direct_backend"
    elif [[ -f "$environment_backend" ]]; then
      input_dir="$environment_context_dir"
      backend_ini="$environment_backend"
    else
      die "No Terraform context '${context_selector}' found. Expected '${direct_backend}' or '${environment_backend}'"
    fi
  fi

  if [[ -n "$backend_ini" ]]; then
    load_backend_config
    configure_provider_context
    cd -- "$base_dir" || die "Unable to enter Terraform context '${base_dir}'"
  fi
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

  if [[ "$summary_format" != "table" || -n "$summary_out" ]] && [[ "$action" != "summ" ]]; then
    die "Summary options are only supported with the 'summ' action"
  fi

  if [[ -n "$tfplan_path" && "$action" != "summ" && "$action" != "apply" ]]; then
    die "The --tfplan option is only supported with 'summ' and 'apply'"
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
    info "Automation mode enabled"
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

  if [[ "$input_dir" != "$base_dir" && -f "${input_dir}/${candidate}" ]]; then
    printf '%s\n' "${input_dir}/${candidate}"
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
  local candidate=""
  local candidate_name=""
  local override=""
  local resolved_override=""

  resolved_tfvars=()
  resolved_tfvars_paths=()

  if ! action_uses_var_files; then
    return 0
  fi

  if [[ "$no_default_tfvars" == false ]]; then
    while IFS= read -r candidate; do
      [[ -f "$candidate" ]] || continue
      candidate_name="${candidate##*/}"
      [[ "$candidate_name" == "terraform.tfvars" ]] && continue
      resolved_tfvars+=("-var-file=${candidate}")
      resolved_tfvars_paths+=("${candidate}")
    done < <(
      export LC_ALL=C
      shopt -s nullglob
      candidates=("${input_dir}"/*.tfvars "${input_dir}"/*.tfvars.json)
      if ((${#candidates[@]} > 0)); then
        printf '%s\n' "${candidates[@]}" | sort
      fi
    )
  fi

  if ((${#tfvars_overrides[@]} > 0)); then
    for override in "${tfvars_overrides[@]}"; do
      resolved_override="$(resolve_override_path "$override")"
      resolved_tfvars+=("-var-file=${resolved_override}")
      resolved_tfvars_paths+=("${resolved_override}")
    done
  fi

  if [[ "$no_default_tfvars" == false && -f "${input_dir}/terraform.tfvars" ]]; then
    resolved_tfvars+=("-var-file=${input_dir}/terraform.tfvars")
    resolved_tfvars_paths+=("${input_dir}/terraform.tfvars")
  fi
}

ensure_initialized() {
  local init_command=("terraform" "init" "-reconfigure")
  local exit_code=0

  work_start "INIT"
  if [[ "$skip_init" == true ]]; then
    work_end skip "--skip-init was provided"
    return 0
  fi

  if ((${#backend_args[@]} > 0)); then
    init_command+=("${backend_args[@]}")
  fi

  if ((${#init_args[@]} > 0)); then
    init_command+=("${init_args[@]}")
  fi

  set +e
  run_cmd "${init_command[@]}"
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
    plan_file="$(mktemp "${TMPDIR:-/tmp}/terraform-summ-plan.XXXXXX")"
    add_cleanup_path "$plan_file"
  fi

  build_terraform_command "plan"
  plan_cmd=("${command_args[@]}" "-out=${plan_file}")

  work_start "PLAN"
  if [[ "$summary_format" == "pr" && "$dry_run" == false ]]; then
    plan_log="$(mktemp "${TMPDIR:-/tmp}/terraform-summ-log.XXXXXX")"
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

  probe_log="$(mktemp "${TMPDIR:-/tmp}/terraform-unlock-log.XXXXXX")"
  probe_plan="$(mktemp "${TMPDIR:-/tmp}/terraform-unlock-plan.XXXXXX")"
  add_cleanup_path "$probe_log"
  add_cleanup_path "$probe_plan"

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

  print_preflight
  if [[ -z "$resolved_lock_id" && "$skip_init" == false ]]; then
    ensure_initialized
  fi

  work_start "LOCK DISCOVERY"
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
  info "Command: terraform force-unlock -force ${resolved_lock_id}"

  confirm_unlock

  unlock_cmd=("terraform" "force-unlock" "-force" "$resolved_lock_id")
  work_run "UNLOCK" "${unlock_cmd[@]}"
}

populate_debug_var_files() {
  local default_var_file=""
  local override=""

  resolved_tfvars_paths=()
  if [[ "$no_default_tfvars" == false ]]; then
    if [[ -f "${input_dir}/terraform.tfvars" ]]; then
      default_var_file="${input_dir}/terraform.tfvars"
    elif [[ -f "${input_dir}/terraform.tfvars.json" ]]; then
      default_var_file="${input_dir}/terraform.tfvars.json"
    fi
    if [[ -n "$default_var_file" ]]; then
      resolved_tfvars_paths+=("$default_var_file")
    fi
  fi

  if ((${#tfvars_overrides[@]} > 0)); then
    for override in "${tfvars_overrides[@]}"; do
      if [[ "$override" = /* && -f "$override" ]]; then
        resolved_tfvars_paths+=("$override")
      elif [[ -f "${input_dir}/${override}" ]]; then
        resolved_tfvars_paths+=("${input_dir}/${override}")
      fi
    done
  fi
}

collect_debug_bundle() {
  local bundle_dir=""
  local providers_file=""
  local workspace_file=""

  print_preflight
  work_start "DEBUG BUNDLE"
  populate_debug_var_files
  bundle_dir="$(mktemp -d "${TMPDIR:-/tmp}/terraform-debug.XXXXXX")"

  {
    printf 'action=%s\n' "$action"
    printf 'base_dir=%s\n' "$base_dir"
    printf 'skip_init=%s\n' "$skip_init"
    printf 'dry_run=%s\n' "$dry_run"
  } > "${bundle_dir}/summary.txt"

  if ((${#resolved_tfvars_paths[@]} > 0)); then
    printf '%s\n' "${resolved_tfvars_paths[@]}" > "${bundle_dir}/var-files.txt"
  else
    printf 'No resolved var files\n' > "${bundle_dir}/var-files.txt"
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
  local override=""

  print_preflight
  work_start "DOCTOR"
  info "Running doctor for ${base_dir}"

  if command -v terraform >/dev/null 2>&1; then
    success "terraform available"
  else
    warn "terraform missing"
    issues=$((issues + 1))
  fi

  if [[ "$no_default_tfvars" == true ]]; then
    info "Default tfvars disabled by --no-default-tfvars"
  else
    info "Default tfvars are optional"
  fi

  if ((${#tfvars_overrides[@]} > 0)); then
    for override in "${tfvars_overrides[@]}"; do
      if [[ "$override" = /* && -f "$override" ]]; then
        success "Override tfvars found: ${override}"
      elif [[ -f "${input_dir}/${override}" ]]; then
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

  success "Doctor completed successfully"
  work_end ok
}

clean_environment() {
  work_start "CLEAN"
  rm -rf -- "${base_dir}/.terraform"
  rm -f -- "${base_dir}/tfplan" "${base_dir}"/tfplan.*
  info "Removed local Terraform artifacts"
  work_end ok
}

run_workspace_list() {
  local workspace_command=("terraform" "workspace" "list")

  if ((${#terraform_args[@]} > 0)); then
    workspace_command+=("${terraform_args[@]}")
  fi

  require_cmd "terraform" "needed for workspace listing"
  print_preflight
  work_run "WORKSPACES" "${workspace_command[@]}"
}

run_tflist_compat() {
  local exit_code=0

  require_cmd "terraform" "needed for tflist"
  require_cmd "tflist" "optional compatibility formatter"
  print_preflight
  ensure_initialized
  work_start "TFLIST"
  if [[ "$dry_run" == true ]]; then
    printf '$ terraform state list | tflist\n'
    work_end dry-run
    return 0
  fi

  set +e
  terraform state list | tflist
  exit_code=$?
  set -e
  if ((exit_code != 0)); then
    work_end fail "TFLIST failed"
    return "$exit_code"
  fi

  work_end ok
}

run_generic_action() {
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
  work_run "$(action_work_name "$action")" "${command_args[@]}"
}

main() {
  parse_cli "$@"
  resolve_terraform_root
  resolve_context
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
      run_workspace_list
      return 0
      ;;
  esac

  case "$action" in
    doctor)
      run_doctor
      ;;
    debug-bundle)
      collect_debug_bundle
      ;;
    init)
      require_cmd "terraform" "needed for init"
      print_preflight
      ensure_initialized
      ;;
    summ)
      run_summary
      ;;
    tlock)
      require_cmd "terraform" "needed for tlock"
      run_provider_lock
      ;;
    unlock)
      run_unlock
      ;;
    tflist)
      run_tflist_compat
      ;;
    *)
      run_generic_action
      ;;
  esac
}

main "$@"
