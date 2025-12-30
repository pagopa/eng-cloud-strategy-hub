#!/bin/bash

# set -x  # Uncomment this line to enable debug mode

#
# This script allows you to perform a whole series of CRUD operations on the sops encrypted file,
# allowing for example to generate the new file or to modify the values ​​of the encrypted file.
# To do this, the script uses an ini file called secrets.ini that contains the name of the kv
# and the key dedicated to sops that takes care of crypting and uncrypting the file.
# This file in saved under a folder structure like this
#    ./secrets/<kvname>/<env>/secret.ini
# kvname is the suffix of the key vault
#

#
# How to use `sh sops.sh`
#
# ℹ️ This script allows you to create a sops file with the relative azure key.
# ℹ️ It also allows you to edit the secrets and add them with the script.
#
# ℹ️ The script uses an inventory file under:
#     "./secrets/<kvname>/<env>/secret.ini"
#     where <kvname> is the key vault name provided as parameter.
#
# Esempi di utilizzo:
#
# ./sops.sh d mykv itn-dev
#    -> decrypt json file using a specified key vault and environment
#
# ./sops.sh s mykv itn-dev
#    -> search in enc file using a specified key vault and environment
#
# ./sops.sh n mykv itn-dev
#    -> create new encrypted json template file using a specified key vault and environment
#
# ./sops.sh a mykv itn-dev
#    -> add a new secret record to the encrypted json file using a specified key vault and environment
#
# ./sops.sh e mykv itn-dev
#    -> edit the encrypted json file using a specified key vault and environment
#
# ./sops.sh f mykv itn-dev
#    -> encrypt an external json file (path is requested at runtime) into the default sops file using a specified key vault and environment
#

# Extract parameters: action, kvname, env
action=$1
kvname=$2
env=$3
shift 3
# shellcheck disable=SC2034
other=( "$@" )

if [ -z "$action" ]; then
  helpmessage=$(cat <<EOF
ℹ️ Please follow this example on how to use the script:

./sops.sh d <kvname> <env>
    example: ./sops.sh d mykv itn-dev
    example: ./sops.sh decrypt mykv itn-dev

./sops.sh s <kvname> <env>
    example: ./sops.sh s mykv itn-dev
    example: ./sops.sh search mykv itn-dev

./sops.sh n <kvname> <env>
    example: ./sops.sh n mykv itn-dev
    example: ./sops.sh new mykv itn-dev

./sops.sh a <kvname> <env>
    example: ./sops.sh a mykv itn-dev
    example: ./sops.sh add mykv itn-dev

./sops.sh e <kvname> <env>
    example: ./sops.sh e mykv itn-dev
    example: ./sops.sh edit mykv itn-dev

./sops.sh f <kvname> <env>
    example: ./sops.sh f mykv itn-dev
    example: ./sops.sh file-encrypt mykv itn-dev

EOF
)
  echo "$helpmessage"
  exit 0
fi

if [ -z "$kvname" ]; then
  echo "❌ Error: kvname parameter is missing."
  exit 1
fi

if [ -z "$env" ]; then
  echo "env should be something like: itn-dev, itn-uat or itn-prod."
  exit 0
fi

echo "🔨 Mandatory parameters are correct"
file_crypted=""
kv_name=""
kv_sops_key_name=""

# shellcheck disable=SC1090
source "./secrets/$kvname/$env/secret.ini"

echo "🔨 All variables loaded"

# Check if kv_name and file_crypted variables are not empty
if [ -z "${kv_name}" ]; then
  echo "❌ Error: kv_name variable is not defined correctly."
  exit 1
fi

if [ -z "$file_crypted" ]; then
  echo "❌ Error: file_crypted variable is not defined correctly."
  exit 1
fi

encrypted_file_path="./secrets/$kvname/$env/$file_crypted"

# Check if the key exists in the Key Vault
# shellcheck disable=SC2154
kv_key_url=$(az keyvault key show --vault-name "$kv_name" --name "$kv_sops_key_name" --query "key.kid" -o tsv)
if [ -z "$kv_key_url" ]; then
  echo "❌ The key does not exist."
  exit 1
fi
echo "[INFO] Key URL: $kv_key_url"

echo "🔨 Key URL loaded correctly"

if echo "d decrypt a add s search n new e edit f file-encrypt di decryptignore" | grep -w "$action" > /dev/null; then
  case $action in
    "d"|"decrypt")
      sops --decrypt --azure-kv "$kv_key_url" "$encrypted_file_path"
      if [ $? -eq 1 ]; then
        echo "❌ File $encrypted_file_path NOT encrypted"
        exit 0
      fi
      ;;
    "di"|"decryptignore")
      sops --decrypt --ignore-mac --azure-kv "$kv_key_url" "$encrypted_file_path"
      if [ $? -eq 1 ]; then
        echo "❌ File $encrypted_file_path NOT encrypted"
        exit 0
      fi
      ;;
    "s"|"search")
      read -r -p 'key: ' key
      sops --decrypt --azure-kv "$kv_key_url" "$encrypted_file_path" | grep -i "$key"
      ;;
    "a"|"add")
      read -r -p 'key: ' key
      read -r -p 'value: ' value
      sops -i --set '["'"$key"'"] "'"$value"'"' --azure-kv "$kv_key_url" "$encrypted_file_path"
      echo "✅ Added key"
      ;;
    "n"|"new")
      if [ -f "$encrypted_file_path" ]; then
        echo "⚠️ file $encrypted_file_path already exists"
        exit 0
      fi
      echo "{}" > "$encrypted_file_path"
      sops --encrypt -i --azure-kv "$kv_key_url" "$encrypted_file_path"
      echo "✅ created new file for sops"
      ;;
    "e"|"edit")
      if [ ! -f "$encrypted_file_path" ]; then
        echo "⚠️ file $encrypted_file_path not found"
        exit 1
      fi

      sops --azure-kv "$kv_key_url" "$encrypted_file_path"
      echo "✅ edit file completed"
      ;;
    "f"|"file-encrypt")
      read -r -p 'file: ' file
      sops --encrypt --azure-kv "$kv_key_url" "./secrets/$kvname/$env/$file" > "$encrypted_file_path"
      ;;
  esac
else
  echo "⚠️ Action not allowed."
  exit 1
fi
