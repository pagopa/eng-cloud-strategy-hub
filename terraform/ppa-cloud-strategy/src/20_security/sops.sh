#!/bin/bash

# This script manages SOPS-encrypted secrets using AWS KMS.
# It expects a config ini file under:
#   ./env/<env>/sops_<scope>.ini

action=$1
kvname=$2
env=$3
shift 3
# shellcheck disable=SC2034
other=( "$@" )

if [ -z "$action" ]; then
  helpmessage=$(cat <<EOF
ℹ️ Please follow this example on how to use the script:

./sops.sh d <scope> <env>
    example: ./sops.sh d core ita-dev
    example: ./sops.sh decrypt core ita-dev

./sops.sh s <scope> <env>
    example: ./sops.sh s core ita-dev
    example: ./sops.sh search core ita-dev

./sops.sh n <scope> <env>
    example: ./sops.sh n core ita-dev
    example: ./sops.sh new core ita-dev

./sops.sh a <scope> <env>
    example: ./sops.sh a core ita-dev
    example: ./sops.sh add core ita-dev

./sops.sh e <scope> <env>
    example: ./sops.sh e core ita-dev
    example: ./sops.sh edit core ita-dev

./sops.sh f <scope> <env>
    example: ./sops.sh f core ita-dev
    example: ./sops.sh file-encrypt core ita-dev
EOF
)
  echo "$helpmessage"
  exit 0
fi

if [ -z "$kvname" ]; then
  echo "❌ Error: scope parameter is missing."
  exit 1
fi

if [ -z "$env" ]; then
  echo "env should be something like: italy-dev, italy-uat or italy-prod."
  exit 0
fi

if [ -z "$(command -v sops)" ]; then
  echo "❌ Error: sops is not installed or not in PATH."
  exit 1
fi

echo "🔨 Mandatory parameters are correct"
file_crypted=""
kms_key_arn=""

secret_ini_path="./env/$env/sops_${kvname}.ini"
if [ ! -f "$secret_ini_path" ]; then
  echo "❌ Error: missing config file $secret_ini_path"
  exit 1
fi
# shellcheck disable=SC1090
source "$secret_ini_path"

echo "🔨 All variables loaded"

if [ -z "${kms_key_arn}" ]; then
  echo "❌ Error: kms_key_arn variable is not defined correctly."
  exit 1
fi

if [ -z "$file_crypted" ]; then
  echo "❌ Error: file_crypted variable is not defined correctly."
  exit 1
fi

file_basename="$file_crypted"
if [[ "$file_basename" != "${kvname}_"* ]]; then
  file_basename="${kvname}_${file_basename}"
fi
encrypted_file_path="./env/$env/$file_basename"

if echo "d decrypt a add s search n new e edit f file-encrypt di decryptignore" | grep -w "$action" > /dev/null; then
  case $action in
    "d"|"decrypt")
      sops --decrypt "$encrypted_file_path"
      if [ $? -eq 1 ]; then
        echo "❌ File $encrypted_file_path NOT encrypted"
        exit 0
      fi
      ;;
    "di"|"decryptignore")
      sops --decrypt --ignore-mac "$encrypted_file_path"
      if [ $? -eq 1 ]; then
        echo "❌ File $encrypted_file_path NOT encrypted"
        exit 0
      fi
      ;;
    "s"|"search")
      read -r -p 'key: ' key
      sops --decrypt "$encrypted_file_path" | grep -i "$key"
      ;;
    "a"|"add")
      read -r -p 'key: ' key
      read -r -p 'value: ' value
      sops -i --set '["'"$key"'"] "'"$value"'"' --kms "$kms_key_arn" "$encrypted_file_path"
      echo "✅ Added key"
      ;;
    "n"|"new")
      if [ -f "$encrypted_file_path" ]; then
        echo "⚠️ file $encrypted_file_path already exists"
        exit 0
      fi
      echo "{}" > "$encrypted_file_path"
      sops --encrypt -i --kms "$kms_key_arn" "$encrypted_file_path"
      echo "✅ created new file for sops"
      ;;
    "e"|"edit")
      if [ ! -f "$encrypted_file_path" ]; then
        echo "⚠️ file $encrypted_file_path not found"
        exit 1
      fi
      sops "$encrypted_file_path"
      echo "✅ edit file completed"
      ;;
    "f"|"file-encrypt")
      read -r -p 'file: ' file
      sops --encrypt --kms "$kms_key_arn" "./env/$env/$file" > "$encrypted_file_path"
      ;;
  esac
else
  echo "⚠️ Action not allowed."
  exit 1
fi
