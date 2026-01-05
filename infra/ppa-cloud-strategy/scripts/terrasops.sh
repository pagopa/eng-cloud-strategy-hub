#!/bin/bash
set -euo pipefail   # Enable strict mode

# =================================================================
# Terraform SOPS Secrets Decryption Script
# =================================================================
#
# DESCRIPTION
# -----------
# This script is used by Terraform to decrypt SOPS secrets and export them to JSON.
# It's designed to work with Azure Key Vault and handles the decryption of secrets
# stored in environment-specific directories.
#
# PREREQUISITES
# ------------
# - jq installed
# - SOPS installed
# - Azure CLI configured
# - Proper access to Azure Key Vault
# - Encrypted files in provided "path" directory (e.g., secrets/cicd/itn-dev)
#
# DIRECTORY STRUCTURE
# -----------------
# ./
# ├── secret/
# │   ├── cicd/
# │   │   ├── itn-dev/
# │   │   │   ├── secret.ini
# │   │   │   └── noedit_secret_enc.json
# │   │   └── ... (other environments)
#
# TERRAFORM USAGE
# -------------
# data "external" "terrasops_sh" {
#   program = ["bash", "terrasops.sh"]
#   query = {
#     path = "secrets/cicd/itn-dev"
#   }
# }
#
# LOCAL USAGE EXAMPLES
# ------------------
# 1. Basic usage:
#    echo '{"path": "secrets/cicd/itn-dev"}' | ./terrasops.sh
#
# 2. With debug mode (shows detailed execution steps):
#    echo '{"path": "secrets/cicd/itn-dev"}' | ./terrasops.sh debug
#
# 3. Pretty print output (useful for debugging):
#    echo '{"path": "secrets/cicd/itn-dev"}' | ./terrasops.sh | jq '.'
#
# 4. Save output to file:
#    echo '{"path": "secrets/cicd/itn-dev"}' | ./terrasops.sh > output.json
#
# 5. Debug mode with output redirection (shows process but saves clean JSON):
#    echo '{"path": "secrets/cicd/itn-dev"}' | ./terrasops.sh debug 2>debug.log >output.json
#
# ERROR HANDLING
# -------------
# The script will exit with status code 1 and an error message if:
# - "path" is not specified in the input JSON
# - Configuration files are missing
# - Azure Key Vault parameters are missing/invalid
# - SOPS decryption fails
#
# NOTE
# ----
# ⚠️  Do not add additional echoes to the script in case of the golden path,
#     as the script only needs to return JSON for Terraform
#
# =================================================================

# Check required dependencies
for cmd in jq sops; do
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        echo "❌ ERROR: ${cmd} is not installed or not in PATH" >&2
        exit 1
    fi
done

# Function for debug messages
debug_log() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo "🔍 DEBUG: $1" >&2
    fi
}

# Function for error messages
error_log() {
    echo "❌ ERROR: $1" >&2
}

# Enable debug mode if the first parameter is "debug"
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

# Load configuration
debug_log "📂 Loading configuration file"

file_crypted="PLACEHOLDER_SECRET_INI"
# shellcheck source=/dev/null
source "$secret_ini_path/secret.ini"
# shellcheck source=/dev/null
encrypted_file_path="$secret_ini_path/$file_crypted"

debug_log "🔒 Checking file existence: $encrypted_file_path"
if [ -f "$encrypted_file_path" ]; then
    debug_log "🔑 Extracting Azure Key Vault parameters"
    # Load the values of azure_kv.vault_url and azure_kv.name from the JSON file
    azure_kv_vault_url=$(jq -r '.sops.azure_kv[0].vault_url' "$encrypted_file_path")
    azure_kv_name=$(jq -r '.sops.azure_kv[0].name' "$encrypted_file_path")

    if [ -z "$azure_kv_vault_url" ] || [ -z "$azure_kv_name" ]; then
        error_log "🔐 Unable to load azure_kv.vault_url and azure_kv.name values from JSON file"
        exit 1
    fi

    debug_log "🔓 Decrypting file with SOPS"
    sops -d --azure-kv "$azure_kv_vault_url" "$encrypted_file_path" | jq -c
    debug_log "🎉 Decryption completed"
else
    debug_log "⚠️ Encrypted file not found, returning empty JSON"
    echo "{}" | jq -c
fi
