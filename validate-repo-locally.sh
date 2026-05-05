#!/usr/bin/env bash
#
# Purpose: Run the local GitHub Actions simulator from the repository root.
# Usage examples:
#   ./validate-repo-locally.sh
#   ./validate-repo-locally.sh --interactive
#   ./validate-repo-locally.sh --skip pre-commit

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PYTHON_BIN="${PYTHON_BIN:-python3}"
readonly PYTHON_BIN
RUNNER_PYTHON="${PYTHON_BIN}"
INTERACTIVE_REQUIREMENTS="${SCRIPT_DIR}/tools/validate_repo_locally/requirements.txt"
readonly INTERACTIVE_REQUIREMENTS
INTERACTIVE_VENV_DIR="${SCRIPT_DIR}/tools/validate_repo_locally/.venv"
readonly INTERACTIVE_VENV_DIR

requires_interactive_bootstrap() {
  local arg=""
  local interactive_requested="false"

  for arg in "$@"; do
    if [[ "${arg}" == "--interactive" ]]; then
      interactive_requested="true"
      continue
    fi

    if [[ "${arg}" == "--help" || "${arg}" == "-h" || "${arg}" == "--list" ]]; then
      return 1
    fi
  done

  [[ "${interactive_requested}" == "true" ]]
}

hash_file() {
  local file_path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file_path}" | awk '{print $1}'
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file_path}" | awk '{print $1}'
    return 0
  fi

  "${PYTHON_BIN}" -c 'from pathlib import Path; import hashlib, sys; print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())' "${file_path}"
}

ensure_interactive_environment() {
  local venv_python="${INTERACTIVE_VENV_DIR}/bin/python"
  local stamp_file="${INTERACTIVE_VENV_DIR}/.requirements.sha256"
  local current_hash=""
  local installed_hash=""

  if [[ ! -f "${INTERACTIVE_REQUIREMENTS}" ]]; then
    printf '❌ Missing interactive requirements file: %s\n' "${INTERACTIVE_REQUIREMENTS}" >&2
    exit 1
  fi

  if [[ ! -x "${venv_python}" ]]; then
    printf 'ℹ️  Creating interactive virtual environment in %s\n' "${INTERACTIVE_VENV_DIR}"
    "${PYTHON_BIN}" -m venv "${INTERACTIVE_VENV_DIR}"
  fi

  current_hash="$(hash_file "${INTERACTIVE_REQUIREMENTS}")"
  if [[ -f "${stamp_file}" ]]; then
    installed_hash="$(<"${stamp_file}")"
  fi

  if [[ "${current_hash}" != "${installed_hash}" ]]; then
    printf 'ℹ️  Installing interactive dependencies from %s\n' "${INTERACTIVE_REQUIREMENTS}"
    "${venv_python}" -m pip install \
      --only-binary=:all: \
      --require-hashes \
      --requirement "${INTERACTIVE_REQUIREMENTS}"
    printf '%s\n' "${current_hash}" > "${stamp_file}"
  fi

  RUNNER_PYTHON="${venv_python}"
}

if requires_interactive_bootstrap "$@"; then
  ensure_interactive_environment
fi

exec "${RUNNER_PYTHON}" "${SCRIPT_DIR}/tools/validate_repo_locally/validate_repo_locally.py" \
  --root "${SCRIPT_DIR}" \
  "$@"
