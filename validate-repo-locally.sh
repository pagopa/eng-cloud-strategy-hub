#!/usr/bin/env bash
#
# Purpose: Run the local GitHub Actions simulator from the repository root.
# Usage examples:
#   ./validate-repo-locally.sh
#   ./validate-repo-locally.sh --yes
#   ./validate-repo-locally.sh --skip pre-commit

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
PYTHON_BIN="${PYTHON_BIN:-python3}"
readonly PYTHON_BIN

exec "${PYTHON_BIN}" "${SCRIPT_DIR}/tools/local_actions/runner.py" \
  --root "${SCRIPT_DIR}" \
  "$@"
