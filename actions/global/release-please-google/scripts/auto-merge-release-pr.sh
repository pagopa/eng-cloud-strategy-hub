#!/usr/bin/env bash
#
# Purpose: Resolve release-please pull requests conservatively and optionally enable auto-merge.
# Usage examples:
#   GITHUB_TOKEN=fake RP_TARGET_BRANCH=main RP_AUTO_MERGE=false RP_MERGE_METHOD=squash GITHUB_OUTPUT=/tmp/out ./auto-merge-release-pr.sh
#   GITHUB_TOKEN=fake RP_TARGET_BRANCH=main RP_AUTO_MERGE=true RP_MERGE_METHOD=squash GITHUB_OUTPUT=/tmp/out ./auto-merge-release-pr.sh

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
TEMP_DIR=""

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

trap cleanup EXIT

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
  echo "❌ ${SCRIPT_NAME}: $*" >&2
}

write_output() {
  local key="$1"
  local value="$2"

  if [[ -z "${GITHUB_OUTPUT:-}" ]]; then
    log_error "GITHUB_OUTPUT is required."
    exit 1
  fi

  printf '%s=%s\n' "$key" "$value" >> "${GITHUB_OUTPUT}"
}

require_env() {
  local name="$1"

  if [[ -z "${!name:-}" ]]; then
    log_error "${name} is required."
    exit 1
  fi
}

validate_bool_like() {
  local name="$1"

  case "${!name}" in
    true|false) ;;
    *)
      log_error "${name} must be 'true' or 'false'."
      exit 1
      ;;
  esac
}

validate_merge_method() {
  case "${RP_MERGE_METHOD}" in
    merge|squash|rebase) ;;
    *)
      log_error "RP_MERGE_METHOD must be one of: merge, squash, rebase."
      exit 1
      ;;
  esac
}

normalize_release_please_outputs() {
  python3 - <<'PY'
import json
import os
import sys


def load_payload(raw: str, default):
    if not raw:
        return default
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return default


target_branch = os.environ["RP_TARGET_BRANCH"]
server_url = os.environ.get("GITHUB_SERVER_URL", "https://github.com").rstrip("/")
repository = os.environ.get("GITHUB_REPOSITORY", "")
prs = load_payload(os.environ.get("RP_PRS", ""), [])
pr = load_payload(os.environ.get("RP_PR", ""), None)

if isinstance(pr, dict):
    prs.append(pr)

normalized = []
seen_numbers = set()

for item in prs:
    if not isinstance(item, dict):
        continue
    number = item.get("number")
    head_branch = item.get("headBranchName", "")
    base_branch = item.get("baseBranchName", "")
    title = item.get("title", "")
    if not isinstance(number, int):
        continue
    if number in seen_numbers:
        continue
    if not head_branch.startswith("release-please--"):
        continue
    if base_branch != target_branch:
        continue
    if "chore: release" not in title.lower():
        continue
    seen_numbers.add(number)
    normalized.append(
        {
            "number": number,
            "url": f"{server_url}/{repository}/pull/{number}" if repository else str(number),
            "title": title,
            "headBranchName": head_branch,
            "baseBranchName": base_branch,
            "source": "release-please-output",
        }
    )

print(json.dumps(normalized, separators=(",", ":")))
PY
}

discover_release_please_prs() {
  gh pr list \
    --state open \
    --base "${RP_TARGET_BRANCH}" \
    --json number,title,url,headRefName,baseRefName,author | python3 - <<'PY'
import json
import sys

items = json.load(sys.stdin)
normalized = []

for item in items:
    author = item.get("author") or {}
    author_login = (author.get("login") or "").lower()
    if not item.get("headRefName", "").startswith("release-please--"):
        continue
    if "chore: release" not in (item.get("title") or "").lower():
        continue
    if "[bot]" not in author_login and not author_login.startswith("app/") and author_login != "github-actions":
        continue
    normalized.append(
        {
            "number": item["number"],
            "url": item["url"],
            "title": item["title"],
            "headBranchName": item["headRefName"],
            "baseBranchName": item["baseRefName"],
            "source": "gh-fallback",
            "author": author.get("login", ""),
        }
    )

print(json.dumps(normalized, separators=(",", ":")))
PY
}

emit_pr_outputs() {
  local prs_json="$1"
  local first_pr_url

  first_pr_url="$(PRS_JSON="${prs_json}" python3 - <<'PY'
import json
import os

items = json.loads(os.environ["PRS_JSON"])
print(items[0]["url"] if items else "")
PY
)"

  write_output "pr" "${first_pr_url}"
  write_output "prs" "${prs_json}"
  write_output "auto_merge_enabled" "${RP_AUTO_MERGE}"
}

enable_auto_merge() {
  local prs_json="$1"
  local stdout_file
  local stderr_file
  local pr_spec
  local pr_number
  local pr_url

  stdout_file="${TEMP_DIR}/gh.stdout"
  stderr_file="${TEMP_DIR}/gh.stderr"

  while IFS='|' read -r pr_number pr_url; do
    if ! gh pr merge "${pr_url}" --auto --"${RP_MERGE_METHOD}" >"${stdout_file}" 2>"${stderr_file}"; then
      local error_output

      error_output="$(<"${stderr_file}")"
      if grep -Eqi 'resource not accessible by integration|insufficient|permission|forbidden|403' "${stderr_file}"; then
        log_error "The provided github_token does not have enough permissions to enable auto-merge for PR #${pr_number}."
      elif grep -Eqi 'auto-merge.*(disabled|not enabled)|enable auto-merge' "${stderr_file}"; then
        log_error "Repository auto-merge is not enabled or is unavailable for PR #${pr_number}."
      elif grep -Eqi 'already.*auto-merge|auto-merge.*already' "${stderr_file}"; then
        log_warn "Auto-merge was already enabled for PR #${pr_number}."
        continue
      else
        log_error "gh pr merge --auto failed for PR #${pr_number}: ${error_output}"
      fi
      exit 1
    fi

    log_success "Enabled auto-merge for PR #${pr_number} with '${RP_MERGE_METHOD}'."
  done < <(
    PRS_JSON="${prs_json}" python3 - <<'PY'
import json
import os

for item in json.loads(os.environ["PRS_JSON"]):
    print(f"{item['number']}|{item['url']}")
PY
  )
}

main() {
  local resolved_prs

  TEMP_DIR="$(mktemp -d)"

  require_env "GITHUB_TOKEN"
  require_env "RP_TARGET_BRANCH"
  require_env "RP_AUTO_MERGE"
  require_env "RP_MERGE_METHOD"
  validate_bool_like "RP_AUTO_MERGE"
  validate_bool_like "RP_DEBUG"
  validate_merge_method

  resolved_prs="$(normalize_release_please_outputs)"
  if [[ "${RP_DEBUG}" == "true" ]]; then
    log_info "release-please outputs candidate PRs: ${resolved_prs}"
  fi

  if [[ "${resolved_prs}" == "[]" ]]; then
    resolved_prs="$(discover_release_please_prs)"
    if [[ "${RP_DEBUG}" == "true" ]]; then
      log_info "gh fallback candidate PRs: ${resolved_prs}"
    fi
  fi

  emit_pr_outputs "${resolved_prs}"

  if [[ "${resolved_prs}" == "[]" ]]; then
    if [[ "${RP_AUTO_MERGE}" == "true" ]]; then
      log_error "No open release-please pull request was found for target branch '${RP_TARGET_BRANCH}'."
      exit 1
    fi

    log_info "No release-please pull request was resolved."
    exit 0
  fi

  if [[ "${RP_AUTO_MERGE}" == "false" ]]; then
    log_info "Auto-merge is disabled. Release PRs were resolved without merge operations."
    exit 0
  fi

  enable_auto_merge "${resolved_prs}"
}

main "$@"
