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
secret_env=""
scope=""
secret_path=""
eval "$(jq -r 'def norm: ( . // "" | tostring ); @sh "export secret_env=\(.env | norm) scope=\(.scope | norm) secret_path=\(.path | norm)"')"

if [[ -n "$secret_env" && -n "$scope" ]]; then
  secret_ini_path="./env/$secret_env/sops_${scope}.ini"
  env_dir="./env/$secret_env"
elif [[ -n "$secret_path" ]]; then
  if [[ -f "$secret_path" ]]; then
    secret_ini_path="$secret_path"
    env_dir="$(dirname "$secret_path")"
  elif [[ -d "$secret_path" && -n "$scope" ]]; then
    secret_ini_path="$secret_path/sops_${scope}.ini"
    env_dir="$secret_path"
  else
    error_log "🚫 Invalid path or missing scope in Terraform JSON input"
    exit 1
  fi
else
  error_log "🚫 Missing env/scope in Terraform JSON input"
  exit 1
fi

debug_log "🌍 Config path set to: $secret_ini_path"

debug_log "📂 Loading configuration file"
file_crypted="PLACEHOLDER_SECRET_INI"
# shellcheck source=/dev/null
source "$secret_ini_path"

file_basename="$file_crypted"
if [[ "$file_basename" != "${scope}_"* ]]; then
  file_basename="${scope}_${file_basename}"
fi
encrypted_file_path="$env_dir/$file_basename"

debug_log "🔒 Checking file existence: $encrypted_file_path"
if [ -f "$encrypted_file_path" ]; then
  debug_log "🔓 Decrypting file with SOPS"
  sops -d "$encrypted_file_path" | jq -c
  debug_log "🎉 Decryption completed"
else
  debug_log "⚠️ Encrypted file not found, returning empty JSON"
  echo "{}" | jq -c
fi
