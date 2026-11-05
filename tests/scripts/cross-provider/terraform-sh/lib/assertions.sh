#!/usr/bin/env bash
#
# Purpose: Minimal assertions for the Terraform wrapper simulation suite.
# Usage examples:
#   source ./lib/assertions.sh
#   assert_contains "$output" "needle" "message"

set -euo pipefail

fail() {
  printf '❌ %s\n' "$*" >&2
  return 1
}

success() {
  printf '✅ %s\n' "$*"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  [[ "$expected" == "$actual" ]] || fail "${message}: expected '${expected}', got '${actual}'"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" == *"$needle"* ]] || fail "${message}: missing '${needle}'"
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local message="$3"

  [[ "$haystack" != *"$needle"* ]] || fail "${message}: found unexpected '${needle}'"
}

assert_file_contains() {
  local file_path="$1"
  local needle="$2"
  local message="$3"
  local content=""

  [[ -f "$file_path" ]] || fail "${message}: file '${file_path}' not found"
  content="$(cat "$file_path")"
  assert_contains "$content" "$needle" "$message"
}

assert_file_not_exists() {
  local file_path="$1"
  local message="$2"

  [[ ! -e "$file_path" ]] || fail "${message}: '${file_path}' still exists"
}

assert_path_exists() {
  local file_path="$1"
  local message="$2"

  [[ -e "$file_path" ]] || fail "${message}: '${file_path}' not found"
}
