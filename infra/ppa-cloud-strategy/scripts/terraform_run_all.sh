#!/bin/bash



#
# bash .utils/terraform_run_all.sh <Action>
# bash .utils/terraform_run_all.sh init
#

# 'set -e' tells the shell to exit if any of the foreground command fails,
# i.e. exits with a non-zero status.
set -eu

pids=()
ACTION="$1"

array=(
    'src/10_networking::itn-dev'
    'src/11_packer::itn-dev'
    'src/20_security_kv::itn-dev'
    'src/30_core::itn-dev'
    'src/31_aks_italy::itn-dev'
    'src/40_platform::itn-dev'
    'src/41_platform_coder::itn-dev'
    'src/49_grafanaconf::itn-dev'
    'src/70_domains/idpay_common::itn-dev'
    'src/70_domains/idpay_security::itn-dev'
    'src/70_domains/idpay_app::itn-dev'
    'src/70_domains/srtp_common::itn-dev'
    'src/70_domains/srtp_security::itn-dev'
    'src/70_domains/srtp_app::itn-dev'
    'src/70_domains/mcshared-common::itn-dev'
    'src/70_domains/mcshared-app::itn-dev'
    'src/70_domains/mcshared-security::itn-dev'
    'src/90_aws/01_init::central-dev'
    'src/90_aws/02_core::central-dev'
    'src/91_github/idpay::itn-dev'
    'src/91_github/srtp::itn-dev'
    'src/91_github/mcshared::itn-dev'
)

function rm_terraform {
    find . \( -iname ".terraform*" ! -iname ".terraform-docs*" ! -iname ".terraform-version" ! -iname ".terraform.lock.hcl" \) -print0 | xargs -0 rm -rf
}

# echo "[INFO] 🪚  Delete all .terraform folders"
# rm_terraform

echo "[INFO] 🏁 Init all terraform repos"
for index in "${array[@]}" ; do
    FOLDER="${index%%::*}"
    COMMAND="${index##*::}"
    pushd "$(pwd)/${FOLDER}"
        echo "$FOLDER - $COMMAND"
        echo "🔬 folder: $(pwd) in under terraform: $ACTION action"
        sh terraform.sh "$ACTION" "$COMMAND"

         terraform providers lock \
           -platform=windows_amd64 \
           -platform=darwin_amd64 \
           -platform=darwin_arm64 \
           -platform=linux_amd64 &

        pids+=($!)
    popd
done


# Wait for each specific process to terminate.
# Instead of this loop, a single call to 'wait' would wait for all the jobs
# to terminate, but it would not give us their exit status.
#
for pid in "${pids[@]}"; do
  #
  # Waiting on a specific PID makes the wait command return with the exit
  # status of that process. Because of the 'set -e' setting, any exit status
  # other than zero causes the current shell to terminate with that exit
  # status as well.
  #
  wait "$pid"
done
