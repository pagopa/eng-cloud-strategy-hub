#!/bin/bash
set -euo pipefail

#
# 💡 How to use
# sh terraform.sh apply <project name>
# sh terraform.sh apply dev-pagopa
#

ACTION="${1:-}"
DIR_PROJECT="${2:-}"

SCRIPT_PATH="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CURRENT_DIRECTORY="$(basename "$SCRIPT_PATH")"
OTHER_ARGS=()
if [ "$#" -ge 2 ]; then
  shift 2
  OTHER_ARGS=("$@")
fi
# GCP project used for Terraform state storage (project name: organization).
TF_STATE_PROJECT_ID="organization-443016"
# must be project in lower case

info() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*"
}

err() {
  echo "[ERROR] $*"
}

die() {
  err "$@"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  sh terraform.sh <action> <project> [terraform args]

Examples:
  sh terraform.sh apply dev-pagopa
  sh terraform.sh plan dev-pagopa -var="foo=bar"
EOF
}

run_terraform() {
  local action="$1"
  shift
  info "⏳ Running Terraform: ${action} ${*}"
  terraform "${action}" \
    -compact-warnings \
    "$@"
}

check_command() {
  local cmd="$1"
  if ! command -v "$cmd" > /dev/null 2>&1; then
    die "❌ Required command not found: ${cmd}"
  fi
}

check_gcp_login() {
  case "${CICD_ENABLE:-}" in
    1|true|TRUE|yes|YES)
      info "🧪 CICD_ENABLE set, skipping GCP login check"
      return 0
      ;;
  esac

  local active_account
  active_account="$(gcloud auth list --filter="status:ACTIVE" --format="value(account)" 2>/dev/null || true)"
  if [ -z "$active_account" ]; then
    die "❌ No active gcloud account found. Run 'gcloud auth login' before using this script."
  fi
  info "✅ gcloud authenticated as: ${active_account}"
}

init_backend() {
  info "🎬 Init Terraform backend for: ${DIR_PROJECT}"
  terraform init \
    -reconfigure \
    -backend-config="$BACKEND_VARS"
}

main() {
  info "📁 Current directory: ${CURRENT_DIRECTORY}"

  if [ -z "$ACTION" ]; then
    usage
    die "❌ Missing ACTION. Allowed: init, plan, apply, refresh, import, output, state, taint, destroy."
  fi

  if [ -z "$DIR_PROJECT" ]; then
    usage
    die "❌ Missing DIR_PROJECT. Example: dev, uat, prod."
  fi

  if [[ ! "$DIR_PROJECT" =~ ^[a-z0-9-]+$ ]]; then
    die "❌ DIR_PROJECT must be lowercase letters, numbers, or hyphens."
  fi

  PROJECT_DIR="./projects/${DIR_PROJECT}"
  BACKEND_VARS="${PROJECT_DIR}/backend.tfvars"
  TF_VARS="${PROJECT_DIR}/terraform.tfvars.json"

  if [ ! -d "$PROJECT_DIR" ]; then
    die "❌ Project directory not found: ${PROJECT_DIR}"
  fi

  check_command "gcloud"
  check_command "terraform"
  check_gcp_login

  #
  # 🏁 Source & init shell
  #

  # project set
  info "🔧 Setting GCP project: ${TF_STATE_PROJECT_ID} (used to store Terraform state files)"
  gcloud config set project "${TF_STATE_PROJECT_ID}"

  # if using cygwin, we have to transcode the WORKDIR
  if [[ ${WORKDIR:-} == /cygdrive/* ]]; then
    WORKDIR=$(cygpath -w "$WORKDIR")
  fi

  export TF_VAR_project_target="${DIR_PROJECT}"

  #
  # 🌎 Terraform
  #
  ALLOWED_ACTIONS="init plan apply refresh import output state taint destroy"
  if ! echo "$ALLOWED_ACTIONS" | grep -w "$ACTION" > /dev/null; then
    die "🚧 ACTION not allowed. Allowed: ${ALLOWED_ACTIONS}"
  fi

  if [ ! -f "$BACKEND_VARS" ]; then
    die "❌ Backend config not found: ${BACKEND_VARS}"
  fi

  case "$ACTION" in
    init)
      init_backend
      return 0
      ;;
    output|state|taint)
      init_backend
      terraform "$ACTION" "${OTHER_ARGS[@]+"${OTHER_ARGS[@]}"}"
      return 0
      ;;
    *)
      if [ ! -f "$TF_VARS" ]; then
        warn "⚠️ Vars file not found: ${TF_VARS} (continuing without -var-file)"
        init_backend
        run_terraform "${ACTION}" "${OTHER_ARGS[@]+"${OTHER_ARGS[@]}"}"
        info "✅ Completed: ${ACTION} on ${DIR_PROJECT}"
        return 0
      fi

      init_backend
      run_terraform "${ACTION}" -var-file="$TF_VARS" "${OTHER_ARGS[@]+"${OTHER_ARGS[@]}"}"
      info "✅ Completed: ${ACTION} on ${DIR_PROJECT}"
      return 0
      ;;
  esac
}

main
