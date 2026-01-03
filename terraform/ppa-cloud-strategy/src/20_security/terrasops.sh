#!/bin/bash
set -euo pipefail

# Terraform SOPS secrets decryption script (AWS KMS).

for cmd in jq sops; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "❌ ERROR: ${cmd} is not installed or not in PATH" >&2
    exit 1
  fi
done

debug_log() {
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "🔍 DEBUG: $1" >&2
  fi
}

error_log() {
  echo "❌ ERROR: $1" >&2
}

if [[ "${1:-}" == "debug" ]]; then
  export DEBUG=true
  debug_log "🐛 Debug mode enabled"
fi

debug_log "📝 Parsing JSON input from Terraform"
eval "$(jq -r '@sh "export secret_ini_path=\(.path)"')"

if [[ -z "$secret_ini_path" ]]; then
  error_log "🚫 Path not specified in Terraform JSON input"
  exit 1
fi
debug_log "🌍 Path set to: $secret_ini_path"

debug_log "📂 Loading configuration file"
file_crypted="PLACEHOLDER_SECRET_INI"
# shellcheck source=/dev/null
source "$secret_ini_path/secret.ini"
# shellcheck source=/dev/null
encrypted_file_path="$secret_ini_path/$file_crypted"

debug_log "🔒 Checking file existence: $encrypted_file_path"
if [ -f "$encrypted_file_path" ]; then
  debug_log "🔓 Decrypting file with SOPS"
  sops -d "$encrypted_file_path" | jq -c
  debug_log "🎉 Decryption completed"
else
  debug_log "⚠️ Encrypted file not found, returning empty JSON"
  echo "{}" | jq -c
fi
